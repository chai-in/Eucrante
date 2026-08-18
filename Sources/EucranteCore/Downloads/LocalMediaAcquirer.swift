@preconcurrency import Foundation

public enum BrowserSessionSource: String, Codable, CaseIterable, Identifiable, Sendable {
  case none
  case brave
  case chrome
  case firefox
  case safari

  public var id: Self { self }

  public var displayName: String {
    switch self {
    case .none: "Do not use a browser session"
    case .brave: "Brave"
    case .chrome: "Google Chrome"
    case .firefox: "Firefox"
    case .safari: "Safari"
    }
  }

  fileprivate var ytDLPName: String? {
    switch self {
    case .none: nil
    case .brave: "brave"
    case .chrome: "chrome"
    case .firefox: "firefox"
    case .safari: "safari"
    }
  }
}

public struct LocalToolStatus: Equatable, Sendable {
  public let ready: Bool
  public let downloaderVersion: String?
  public let runtimeVersion: String?

  public init(ready: Bool, downloaderVersion: String?, runtimeVersion: String?) {
    self.ready = ready
    self.downloaderVersion = downloaderVersion
    self.runtimeVersion = runtimeVersion
  }
}

public enum LocalAcquisitionResult: Equatable, Sendable {
  case single(url: URL, suggestedFilename: String)
  case merge(video: URL, audio: URL, suggestedFilename: String)
}

public struct LocalAcquisitionProgress: Equatable, Sendable {
  public let fraction: Double?
  public let bytesCompleted: Int64?
  public let bytesExpected: Int64?

  public init(fraction: Double?, bytesCompleted: Int64?, bytesExpected: Int64?) {
    self.fraction = fraction
    self.bytesCompleted = bytesCompleted
    self.bytesExpected = bytesExpected
  }
}

public protocol LocalMediaAcquiring: Sendable {
  func toolStatus() async -> LocalToolStatus
  func acquire(
    sourceURL: URL,
    preset: EucrantePreset,
    preferences: DownloadPreferences,
    browserSession: BrowserSessionSource,
    workingDirectory: URL,
    progress: @escaping @Sendable (LocalAcquisitionProgress) -> Void
  ) async throws -> LocalAcquisitionResult
}

public actor LocalMediaAcquirer: LocalMediaAcquiring {
  public struct ToolPaths: Equatable, Sendable {
    public let ytDLP: URL
    public let deno: URL

    public init(ytDLP: URL, deno: URL) {
      self.ytDLP = ytDLP
      self.deno = deno
    }

    public static func discover(
      bundle: Bundle = .main,
      environment: [String: String] = ProcessInfo.processInfo.environment,
      currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> ToolPaths {
      let fileManager = FileManager.default
      let bundled = bundle.resourceURL?.appendingPathComponent("Tools", isDirectory: true)
      let development = currentDirectory.appendingPathComponent(
        ".build/eucrante-tools", isDirectory: true)

      func executable(_ overrideKey: String, name: String) -> URL {
        if let override = environment[overrideKey], !override.isEmpty {
          return URL(fileURLWithPath: override)
        }
        if let bundled {
          let candidate = bundled.appendingPathComponent(name)
          if fileManager.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return development.appendingPathComponent(name)
      }

      return ToolPaths(
        ytDLP: executable("EUCRANTE_YTDLP_PATH", name: "yt-dlp"),
        deno: executable("EUCRANTE_DENO_PATH", name: "deno")
      )
    }
  }

  private let tools: ToolPaths
  private let fileManager: FileManager
  private let runner = LocalProcessRunner()

  public init(tools: ToolPaths = .discover(), fileManager: FileManager = .default) {
    self.tools = tools
    self.fileManager = fileManager
  }

  public func toolStatus() async -> LocalToolStatus {
    guard toolsAreExecutable else {
      return LocalToolStatus(ready: false, downloaderVersion: nil, runtimeVersion: nil)
    }
    let ytDLPVersion = try? await runner.run(
      executable: tools.ytDLP,
      arguments: ["--version"],
      onLine: { _ in }
    ).first
    let denoVersion = try? await runner.run(
      executable: tools.deno,
      arguments: ["--version"],
      onLine: { _ in }
    ).first
    return LocalToolStatus(
      ready: ytDLPVersion != nil && denoVersion != nil,
      downloaderVersion: ytDLPVersion,
      runtimeVersion: denoVersion
    )
  }

  public func acquire(
    sourceURL: URL,
    preset: EucrantePreset,
    preferences: DownloadPreferences,
    browserSession: BrowserSessionSource,
    workingDirectory: URL,
    progress: @escaping @Sendable (LocalAcquisitionProgress) -> Void
  ) async throws -> LocalAcquisitionResult {
    guard toolsAreExecutable else { throw LocalAcquisitionError.toolsMissing }
    try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
    let audioOnly = preset.isAudio || (preset == .custom && preferences.downloadMode == .audio)
    let mute = preset == .custom && preferences.downloadMode == .mute

    if audioOnly {
      let run = try await download(
        sourceURL: sourceURL,
        kind: .audio(maximumBitrate: preset == .appleMusicEfficient ? 256 : nil),
        prefix: "audio",
        browserSession: browserSession,
        videoQuality: preferences.videoQuality,
        workingDirectory: workingDirectory,
        progressScale: 0...1,
        progress: progress
      )
      return .single(
        url: run.url,
        suggestedFilename: preferences.filenameStyle.filename(
          title: run.title,
          creator: run.creator,
          sourceID: run.sourceID,
          pathExtension: run.url.pathExtension
        ))
    }

    let video = try await download(
      sourceURL: sourceURL,
      kind: .video,
      prefix: "video",
      browserSession: browserSession,
      videoQuality: preferences.videoQuality,
      workingDirectory: workingDirectory,
      progressScale: mute ? 0...1 : 0...0.5,
      progress: progress
    )
    if mute {
      return .single(
        url: video.url,
        suggestedFilename: preferences.filenameStyle.filename(
          title: video.title,
          creator: video.creator,
          sourceID: video.sourceID,
          pathExtension: video.url.pathExtension
        ))
    }

    let audio = try await download(
      sourceURL: sourceURL,
      kind: .audio(maximumBitrate: preset == .appleVideoEfficient ? 256 : nil),
      prefix: "audio",
      browserSession: browserSession,
      videoQuality: preferences.videoQuality,
      workingDirectory: workingDirectory,
      progressScale: 0.5...1,
      progress: progress
    )
    return .merge(
      video: video.url,
      audio: audio.url,
      suggestedFilename: preferences.filenameStyle.filename(
        title: video.title,
        creator: video.creator,
        sourceID: video.sourceID,
        pathExtension: "mp4"
      ))
  }

  private enum DownloadKind {
    case video
    case audio(maximumBitrate: Int?)

    func formatSelector(videoQuality: VideoQuality) -> String {
      switch self {
      case .video:
        let height = videoQuality == .maximum ? "" : "[height<=\(videoQuality.rawValue)]"
        return "bestvideo[vcodec^=avc1][ext=mp4]\(height)/best[vcodec^=avc1][ext=mp4]\(height)"
      case .audio(let maximumBitrate):
        let bestAppleAudio =
          "bestaudio[acodec^=mp4a][ext=m4a]/bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]"
        guard let maximumBitrate else { return bestAppleAudio }
        return
          "bestaudio[acodec^=mp4a][ext=m4a][abr<=\(maximumBitrate)]/"
          + "bestaudio[ext=m4a][abr<=\(maximumBitrate)]/"
          + "bestaudio[acodec^=mp4a][abr<=\(maximumBitrate)]/"
          + bestAppleAudio
      }
    }
  }

  private struct DownloadRun {
    let url: URL
    let title: String
    let creator: String?
    let sourceID: String?
  }

  private func download(
    sourceURL: URL,
    kind: DownloadKind,
    prefix: String,
    browserSession: BrowserSessionSource,
    videoQuality: VideoQuality,
    workingDirectory: URL,
    progressScale: ClosedRange<Double>,
    progress: @escaping @Sendable (LocalAcquisitionProgress) -> Void
  ) async throws -> DownloadRun {
    try Task.checkCancellation()
    var arguments = [
      "--ignore-config",
      "--no-playlist",
      "--newline",
      "--progress",
      "--continue",
      "--js-runtimes", "deno:\(tools.deno.path)",
      "--format", kind.formatSelector(videoQuality: videoQuality),
      "--output", workingDirectory.appendingPathComponent("\(prefix).%(ext)s").path,
      "--print", "before_dl:EUCRANTE_TITLE:%(title)s",
      "--print", "before_dl:EUCRANTE_CREATOR:%(uploader|)s",
      "--print", "before_dl:EUCRANTE_ID:%(id)s",
      "--progress-template",
      "download:EUCRANTE_PROGRESS:%(progress.downloaded_bytes)s:%(progress.total_bytes)s:%(progress.total_bytes_estimate)s",
    ]
    if let browser = browserSession.ytDLPName {
      arguments.append(contentsOf: ["--cookies-from-browser", browser])
    }
    arguments.append(sourceURL.absoluteString)

    let metadata = LockedMetadata()
    _ = try await runner.run(executable: tools.ytDLP, arguments: arguments) { line in
      if line.hasPrefix("EUCRANTE_TITLE:") {
        metadata.setTitle(String(line.dropFirst("EUCRANTE_TITLE:".count)))
      } else if line.hasPrefix("EUCRANTE_CREATOR:") {
        metadata.setCreator(String(line.dropFirst("EUCRANTE_CREATOR:".count)))
      } else if line.hasPrefix("EUCRANTE_ID:") {
        metadata.setSourceID(String(line.dropFirst("EUCRANTE_ID:".count)))
      } else if let parsed = Self.parseProgress(line) {
        let lower = progressScale.lowerBound
        let width = progressScale.upperBound - lower
        progress(
          LocalAcquisitionProgress(
            fraction: parsed.fraction.map { lower + ($0 * width) },
            bytesCompleted: parsed.completed,
            bytesExpected: parsed.expected
          ))
      }
    }

    guard let output = try outputFile(prefix: prefix, in: workingDirectory) else {
      throw LocalAcquisitionError.outputMissing
    }
    let values = metadata.values
    let title = FilenameSanitizer.sanitize(values.title ?? sourceURL.host() ?? "Media")
    return DownloadRun(
      url: output,
      title: title,
      creator: values.creator,
      sourceID: values.sourceID
    )
  }

  private var toolsAreExecutable: Bool {
    fileManager.isExecutableFile(atPath: tools.ytDLP.path)
      && fileManager.isExecutableFile(atPath: tools.deno.path)
  }

  private func outputFile(prefix: String, in directory: URL) throws -> URL? {
    try fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
      options: [.skipsHiddenFiles]
    ).first { url in
      guard url.deletingPathExtension().lastPathComponent == prefix,
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
      else { return false }
      return values.isRegularFile == true && (values.fileSize ?? 0) > 0
    }
  }

  private static func parseProgress(
    _ line: String
  ) -> (fraction: Double?, completed: Int64?, expected: Int64?)? {
    guard line.hasPrefix("EUCRANTE_PROGRESS:") else { return nil }
    let values = line.dropFirst("EUCRANTE_PROGRESS:".count).split(
      separator: ":", omittingEmptySubsequences: false)
    guard values.count == 3 else { return nil }
    let completed = Int64(values[0])
    let exact = Int64(values[1])
    let estimate = Int64(values[2])
    let expected = exact ?? estimate
    let fraction = completed.flatMap { completed in
      expected.flatMap { expected in expected > 0 ? Double(completed) / Double(expected) : nil }
    }
    return (fraction.map { min(1, max(0, $0)) }, completed, expected)
  }
}

public enum LocalAcquisitionError: LocalizedError, Equatable, Sendable {
  case toolsMissing
  case processFailed(Int32)
  case outputMissing

  public var errorDescription: String? {
    switch self {
    case .toolsMissing:
      "Eucrante's local media tools are missing or damaged. Reinstall the app."
    case .processFailed:
      "The local media downloader could not finish this link. Check the browser session and try again."
    case .outputMissing:
      "The provider returned no usable media file."
    }
  }
}

private final class LockedMetadata: @unchecked Sendable {
  private let lock = NSLock()
  private var title: String?
  private var creator: String?
  private var sourceID: String?

  var values: (title: String?, creator: String?, sourceID: String?) {
    lock.withLock { (title, creator, sourceID) }
  }

  func setTitle(_ value: String) { lock.withLock { title = value } }
  func setCreator(_ value: String) { lock.withLock { creator = value } }
  func setSourceID(_ value: String) { lock.withLock { sourceID = value } }
}

private final class RunningProcess: @unchecked Sendable {
  let process: Process

  init(_ process: Process) { self.process = process }

  func cancel() {
    if process.isRunning { process.terminate() }
  }
}

private actor LocalProcessRunner {
  func run(
    executable: URL,
    arguments: [String],
    onLine: @escaping @Sendable (String) -> Void
  ) async throws -> [String] {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe
    process.environment = [
      "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
      "LANG": "en_US.UTF-8",
      "LC_ALL": "en_US.UTF-8",
      "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
    ]
    let running = RunningProcess(process)

    return try await withTaskCancellationHandler {
      do {
        try process.run()
      } catch {
        throw LocalAcquisitionError.toolsMissing
      }

      var lines: [String] = []
      for try await line in pipe.fileHandleForReading.bytes.lines {
        if lines.count < 200 { lines.append(line) }
        onLine(line)
      }
      process.waitUntilExit()
      try Task.checkCancellation()
      guard process.terminationReason == .exit, process.terminationStatus == 0 else {
        throw LocalAcquisitionError.processFailed(process.terminationStatus)
      }
      return lines
    } onCancel: {
      running.cancel()
    }
  }
}
