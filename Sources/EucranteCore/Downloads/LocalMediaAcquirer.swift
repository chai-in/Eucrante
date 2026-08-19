@preconcurrency import Foundation

public struct LocalToolStatus: Equatable, Sendable {
  public let ready: Bool
  public let downloaderVersion: String?
  public let runtimeVersion: String?
  public let transcoderVersion: String?

  public init(
    ready: Bool,
    downloaderVersion: String?,
    runtimeVersion: String?,
    transcoderVersion: String?
  ) {
    self.ready = ready
    self.downloaderVersion = downloaderVersion
    self.runtimeVersion = runtimeVersion
    self.transcoderVersion = transcoderVersion
  }
}

public enum LocalAcquisitionResult: Equatable, Sendable {
  case single(url: URL, suggestedFilename: String, metadata: MediaMetadata)
  case merge(video: URL, audio: URL, suggestedFilename: String, metadata: MediaMetadata)
  case transcode(
    video: URL,
    audio: URL?,
    suggestedFilename: String,
    duration: Double?,
    quality: AppleVideoTranscodeQuality,
    metadata: MediaMetadata
  )
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
    cookieFile: URL?,
    workingDirectory: URL,
    progress: @escaping @Sendable (LocalAcquisitionProgress) -> Void
  ) async throws -> LocalAcquisitionResult
}

public protocol LocalMediaPreviewing: Sendable {
  func preview(
    sourceURL: URL,
    cookieFile: URL?,
    workingDirectory: URL
  ) async throws -> MediaPreview
}

public actor LocalMediaAcquirer: LocalMediaAcquiring, LocalMediaPreviewing {
  public struct ToolPaths: Equatable, Sendable {
    public let ytDLP: URL
    public let deno: URL
    public let ffmpeg: URL

    public init(ytDLP: URL, deno: URL, ffmpeg: URL) {
      self.ytDLP = ytDLP
      self.deno = deno
      self.ffmpeg = ffmpeg
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
        deno: executable("EUCRANTE_DENO_PATH", name: "deno"),
        ffmpeg: executable("EUCRANTE_FFMPEG_PATH", name: "ffmpeg")
      )
    }
  }

  private let tools: ToolPaths
  private let fileManager: FileManager
  private let toolCheckTimeout: Duration
  private let runner = LocalProcessRunner()

  public init(
    tools: ToolPaths = .discover(),
    fileManager: FileManager = .default,
    toolCheckTimeout: Duration = .seconds(8)
  ) {
    self.tools = tools
    self.fileManager = fileManager
    self.toolCheckTimeout = toolCheckTimeout
  }

  public func toolStatus() async -> LocalToolStatus {
    guard toolsAreExecutable else {
      return LocalToolStatus(
        ready: false,
        downloaderVersion: nil,
        runtimeVersion: nil,
        transcoderVersion: nil
      )
    }
    let checkHome = fileManager.temporaryDirectory.appendingPathComponent(
      "eucrante-tool-check-\(UUID().uuidString)", isDirectory: true)
    do {
      try LocalProcessRunner.prepareRestrictedEnvironment(
        homeDirectory: checkHome, fileManager: fileManager)
    } catch {
      return LocalToolStatus(
        ready: false,
        downloaderVersion: nil,
        runtimeVersion: nil,
        transcoderVersion: nil
      )
    }
    defer { try? fileManager.removeItem(at: checkHome) }
    let environment = LocalProcessRunner.restrictedEnvironment(homeDirectory: checkHome)
    async let ytDLPVersion = checkedVersion(
      executable: tools.ytDLP,
      arguments: ["--version"],
      environment: environment
    )
    async let denoVersion = checkedVersion(
      executable: tools.deno,
      arguments: ["--version"],
      environment: environment
    )
    async let ffmpegVersion = checkedVersion(
      executable: tools.ffmpeg,
      arguments: ["-version"],
      environment: environment
    )
    let versions = await (ytDLPVersion, denoVersion, ffmpegVersion)
    return LocalToolStatus(
      ready: versions.0 != nil && versions.1 != nil && versions.2 != nil,
      downloaderVersion: versions.0,
      runtimeVersion: versions.1,
      transcoderVersion: versions.2
    )
  }

  private func checkedVersion(
    executable: URL,
    arguments: [String],
    environment: [String: String]
  ) async -> String? {
    let runner = runner
    let timeout = toolCheckTimeout
    return await withTaskGroup(of: String?.self) { group in
      group.addTask {
        try? await runner.run(
          executable: executable,
          arguments: arguments,
          environment: environment,
          onLine: { _ in }
        ).first
      }
      group.addTask {
        try? await Task.sleep(for: timeout)
        return nil
      }
      let first = await group.next() ?? nil
      group.cancelAll()
      return first
    }
  }

  public func acquire(
    sourceURL: URL,
    preset: EucrantePreset,
    preferences: DownloadPreferences,
    cookieFile: URL?,
    workingDirectory: URL,
    progress: @escaping @Sendable (LocalAcquisitionProgress) -> Void
  ) async throws -> LocalAcquisitionResult {
    guard toolsAreExecutable else { throw LocalAcquisitionError.toolsMissing }
    try SecureCredentialFile.prepareDirectory(workingDirectory, fileManager: fileManager)
    let audioOnly = preset.isAudio || (preset == .custom && preferences.downloadMode == .audio)
    let mute = preset == .custom && preferences.downloadMode == .mute

    if audioOnly {
      let run = try await download(
        sourceURL: sourceURL,
        kind: .audio(maximumBitrate: preset == .appleMusicEfficient ? 256 : nil),
        prefix: "audio",
        cookieFile: cookieFile,
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
        ),
        metadata: run.metadata
      )
    }

    let video = try await download(
      sourceURL: sourceURL,
      kind: .video,
      prefix: "video",
      cookieFile: cookieFile,
      videoQuality: preferences.videoQuality,
      workingDirectory: workingDirectory,
      progressScale: mute ? 0...1 : 0...0.5,
      progress: progress
    )
    if mute {
      if video.requiresHEVCTranscode {
        return .transcode(
          video: video.url,
          audio: nil,
          suggestedFilename: preferences.filenameStyle.filename(
            title: video.title,
            creator: video.creator,
            sourceID: video.sourceID,
            pathExtension: "mp4"
          ),
          duration: video.duration,
          quality: preset == .appleVideoEfficient ? .efficient : .best,
          metadata: video.metadata
        )
      }
      return .single(
        url: video.url,
        suggestedFilename: preferences.filenameStyle.filename(
          title: video.title,
          creator: video.creator,
          sourceID: video.sourceID,
          pathExtension: video.url.pathExtension
        ),
        metadata: video.metadata
      )
    }

    let audio = try await download(
      sourceURL: sourceURL,
      kind: .audio(maximumBitrate: preset == .appleVideoEfficient ? 256 : nil),
      prefix: "audio",
      cookieFile: cookieFile,
      videoQuality: preferences.videoQuality,
      workingDirectory: workingDirectory,
      progressScale: 0.5...1,
      progress: progress
    )
    let filename = preferences.filenameStyle.filename(
      title: video.title,
      creator: video.creator,
      sourceID: video.sourceID,
      pathExtension: "mp4"
    )
    if video.requiresHEVCTranscode {
      return .transcode(
        video: video.url,
        audio: audio.url,
        suggestedFilename: filename,
        duration: video.duration,
        quality: preset == .appleVideoEfficient ? .efficient : .best,
        metadata: video.metadata
      )
    }
    return .merge(
      video: video.url,
      audio: audio.url,
      suggestedFilename: filename,
      metadata: video.metadata
    )
  }

  public func preview(
    sourceURL: URL,
    cookieFile: URL?,
    workingDirectory: URL
  ) async throws -> MediaPreview {
    guard toolsAreExecutable else { throw LocalAcquisitionError.toolsMissing }
    try Task.checkCancellation()
    try LocalProcessRunner.prepareRestrictedEnvironment(
      homeDirectory: workingDirectory, fileManager: fileManager)
    var arguments = [
      "--ignore-config",
      "--no-playlist",
      "--no-warnings",
      "--skip-download",
      "--dump-single-json",
      "--js-runtimes", "deno:\(tools.deno.path)",
    ]
    if let cookieFile {
      arguments.append(contentsOf: ["--cookies", cookieFile.path])
    }
    arguments.append(sourceURL.absoluteString)
    let lines = try await runner.run(
      executable: tools.ytDLP,
      arguments: arguments,
      environment: LocalProcessRunner.restrictedEnvironment(homeDirectory: workingDirectory),
      onLine: { _ in }
    )
    guard
      let document = lines.reversed().lazy.compactMap({ line -> PreviewDocument? in
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PreviewDocument.self, from: data)
      }).first
    else {
      throw LocalAcquisitionError.previewUnavailable
    }
    return document.preview(sourceURL: sourceURL)
  }

  private enum DownloadKind {
    case video
    case audio(maximumBitrate: Int?)

    func formatSelector(videoQuality: VideoQuality) -> String {
      switch self {
      case .video:
        return LocalMediaAcquirer.videoFormatSelector(videoQuality: videoQuality)
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
    let codec: String?
    let duration: Double?
    let metadata: MediaMetadata

    var requiresHEVCTranscode: Bool {
      let normalized = codec?.lowercased() ?? ""
      return normalized.hasPrefix("vp9") || normalized.hasPrefix("vp09")
    }
  }

  static func videoFormatSelector(videoQuality: VideoQuality) -> String {
    let height = videoQuality == .maximum ? "" : "[height<=\(videoQuality.rawValue)]"
    let appleFallback =
      "bestvideo[vcodec^=avc1][ext=mp4]\(height)/best[vcodec^=avc1][ext=mp4]\(height)"
    guard videoQuality.prefersWideVideoCodec else { return appleFallback }
    return
      "bestvideo[vcodec^=vp9][dynamic_range=SDR]\(height)/"
      + "bestvideo[vcodec^=vp09][dynamic_range=SDR]\(height)/\(appleFallback)"
  }

  private func download(
    sourceURL: URL,
    kind: DownloadKind,
    prefix: String,
    cookieFile: URL?,
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
      "--print", "before_dl:EUCRANTE_TITLE:%(title|)j",
      "--print", "before_dl:EUCRANTE_TRACK:%(track|)j",
      "--print", "before_dl:EUCRANTE_ARTIST:%(artist,creator,uploader|)j",
      "--print", "before_dl:EUCRANTE_CREATOR:%(uploader,channel|)j",
      "--print", "before_dl:EUCRANTE_ALBUM:%(album|)j",
      "--print", "before_dl:EUCRANTE_ALBUM_ARTIST:%(album_artist|)j",
      "--print", "before_dl:EUCRANTE_COMPOSER:%(composer|)j",
      "--print", "before_dl:EUCRANTE_GENRE:%(genre|)j",
      "--print", "before_dl:EUCRANTE_RELEASE_DATE:%(release_date,upload_date|)j",
      "--print", "before_dl:EUCRANTE_RELEASE_YEAR:%(release_year|)j",
      "--print", "before_dl:EUCRANTE_TRACK_NUMBER:%(track_number|)j",
      "--print", "before_dl:EUCRANTE_TRACK_COUNT:%(track_count|)j",
      "--print", "before_dl:EUCRANTE_DISC_NUMBER:%(disc_number|)j",
      "--print", "before_dl:EUCRANTE_DISC_COUNT:%(disc_count|)j",
      "--print", "before_dl:EUCRANTE_DESCRIPTION:%(description|)j",
      "--print", "before_dl:EUCRANTE_THUMBNAIL:%(thumbnail|)j",
      "--print", "before_dl:EUCRANTE_ID:%(id|)j",
      "--print", "before_dl:EUCRANTE_VCODEC:%(vcodec|)j",
      "--print", "before_dl:EUCRANTE_DURATION:%(duration|)j",
      "--progress-template",
      "download:EUCRANTE_PROGRESS:%(progress.downloaded_bytes)s:%(progress.total_bytes)s:%(progress.total_bytes_estimate)s",
    ]
    if let cookieFile {
      arguments.append(contentsOf: ["--cookies", cookieFile.path])
    }
    arguments.append(sourceURL.absoluteString)

    let metadata = LockedMetadata()
    try LocalProcessRunner.prepareRestrictedEnvironment(
      homeDirectory: workingDirectory, fileManager: fileManager)
    let environment = LocalProcessRunner.restrictedEnvironment(homeDirectory: workingDirectory)
    _ = try await runner.run(
      executable: tools.ytDLP,
      arguments: arguments,
      environment: environment
    ) { line in
      if metadata.consume(line) {
        return
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

    guard
      let output = try Self.outputFile(
        prefix: prefix,
        in: workingDirectory,
        fileManager: fileManager
      )
    else {
      throw LocalAcquisitionError.outputMissing
    }
    let values = metadata.values
    let displayTitle = values.track ?? values.title
    let title = FilenameSanitizer.sanitize(displayTitle ?? sourceURL.host() ?? "Media")
    let artist = values.artist ?? values.creator
    let releaseYear = values.releaseYear ?? values.releaseDate.flatMap { Int($0.prefix(4)) }
    let mediaMetadata = MediaMetadata(
      title: displayTitle,
      artist: artist,
      album: values.album,
      albumArtist: values.albumArtist ?? artist,
      composer: values.composer,
      genre: values.genre,
      year: releaseYear,
      trackNumber: values.trackNumber,
      trackCount: values.trackCount,
      discNumber: values.discNumber,
      discCount: values.discCount,
      description: values.description,
      sourceID: values.sourceID,
      sourceURL: sourceURL,
      artworkURL: values.thumbnail.flatMap(URL.init(string:))
    )
    return DownloadRun(
      url: output,
      title: title,
      creator: artist,
      sourceID: values.sourceID,
      codec: values.codec,
      duration: values.duration,
      metadata: mediaMetadata
    )
  }

  private var toolsAreExecutable: Bool {
    fileManager.isExecutableFile(atPath: tools.ytDLP.path)
      && fileManager.isExecutableFile(atPath: tools.deno.path)
      && fileManager.isExecutableFile(atPath: tools.ffmpeg.path)
  }

  static func outputFile(
    prefix: String,
    in directory: URL,
    fileManager: FileManager = .default
  ) throws -> URL? {
    try fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
      options: [.skipsHiddenFiles]
    ).first { url in
      guard url.deletingPathExtension().lastPathComponent == prefix,
        let values = try? url.resourceValues(
          forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        )
      else { return false }
      return values.isSymbolicLink != true
        && values.isRegularFile == true
        && (values.fileSize ?? 0) > 0
    }
  }

  static func parseProgress(
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

  static func processError(status: Int32, diagnostic: String) -> LocalAcquisitionError {
    let normalized = diagnostic.lowercased()
    if normalized.contains("sign in to confirm")
      || normalized.contains("login required")
      || normalized.contains("cookies are no longer valid")
    {
      return .authenticationRequired
    }
    if normalized.contains("http error 403") || normalized.contains("forbidden") {
      return .accessDenied
    }
    if normalized.contains("requested format is not available") {
      return .formatUnavailable
    }
    return .processFailed(status)
  }
}

public enum LocalAcquisitionError: LocalizedError, Equatable, Sendable {
  case toolsMissing
  case processFailed(Int32)
  case authenticationRequired
  case accessDenied
  case formatUnavailable
  case outputMissing
  case previewUnavailable

  public var errorDescription: String? {
    switch self {
    case .toolsMissing:
      "Eucrante's local media tools are missing or damaged. Reinstall the app."
    case .processFailed:
      "The local media downloader could not finish this link. Refresh Eucrante's YouTube sign-in and try again."
    case .authenticationRequired:
      "YouTube requires a fresh sign-in for this link. Open Eucrante's YouTube settings and sign in again."
    case .accessDenied:
      "YouTube refused the media transfer. Refresh Eucrante's private YouTube sign-in and retry the job."
    case .formatUnavailable:
      "This link does not currently expose media that matches the selected output. Try another preset."
    case .outputMissing:
      "The provider returned no usable media file."
    case .previewUnavailable:
      "Eucrante could not read preview details for this link. You can still try saving it."
    }
  }
}

private struct PreviewDocument: Decodable {
  let id: String?
  let title: String?
  let track: String?
  let artist: String?
  let creator: String?
  let uploader: String?
  let channel: String?
  let album: String?
  let albumArtist: String?
  let composer: String?
  let genre: String?
  let releaseDate: String?
  let releaseYear: Int?
  let uploadDate: String?
  let trackNumber: Int?
  let trackCount: Int?
  let discNumber: Int?
  let discCount: Int?
  let description: String?
  let thumbnail: String?
  let duration: Double?
  let formats: [PreviewFormatDocument]

  enum CodingKeys: String, CodingKey {
    case id, title, track, artist, creator, uploader, channel, album, composer, genre, description
    case thumbnail, duration, formats
    case albumArtist = "album_artist"
    case releaseDate = "release_date"
    case releaseYear = "release_year"
    case uploadDate = "upload_date"
    case trackNumber = "track_number"
    case trackCount = "track_count"
    case discNumber = "disc_number"
    case discCount = "disc_count"
  }

  func preview(sourceURL: URL) -> MediaPreview {
    let resolvedArtist = artist ?? creator ?? uploader ?? channel
    let year =
      releaseYear ?? releaseDate.flatMap { Int($0.prefix(4)) }
      ?? uploadDate.flatMap { Int($0.prefix(4)) }
    return MediaPreview(
      metadata: MediaMetadata(
        title: track ?? title,
        artist: resolvedArtist,
        album: album,
        albumArtist: albumArtist ?? resolvedArtist,
        composer: composer,
        genre: genre,
        year: year,
        trackNumber: trackNumber,
        trackCount: trackCount,
        discNumber: discNumber,
        discCount: discCount,
        description: description,
        sourceID: id,
        sourceURL: sourceURL,
        artworkURL: thumbnail.flatMap(URL.init(string:))
      ),
      duration: duration,
      formats: formats.map(\.previewFormat)
    )
  }
}

private struct PreviewFormatDocument: Decodable {
  let formatID: String
  let ext: String?
  let videoCodec: String?
  let audioCodec: String?
  let width: Int?
  let height: Int?
  let frameRate: Double?
  let totalBitrate: Double?
  let audioBitrate: Double?
  let fileSize: Int64?
  let approximateFileSize: Int64?

  enum CodingKeys: String, CodingKey {
    case ext, width, height
    case formatID = "format_id"
    case videoCodec = "vcodec"
    case audioCodec = "acodec"
    case frameRate = "fps"
    case totalBitrate = "tbr"
    case audioBitrate = "abr"
    case fileSize = "filesize"
    case approximateFileSize = "filesize_approx"
  }

  var previewFormat: MediaPreviewFormat {
    MediaPreviewFormat(
      identifier: formatID,
      container: ext,
      videoCodec: videoCodec,
      audioCodec: audioCodec,
      width: width,
      height: height,
      frameRate: frameRate,
      totalBitrate: totalBitrate,
      audioBitrate: audioBitrate,
      fileSize: fileSize,
      approximateFileSize: approximateFileSize
    )
  }
}

private final class LockedMetadata: @unchecked Sendable {
  private let lock = NSLock()
  private var title: String?
  private var track: String?
  private var artist: String?
  private var creator: String?
  private var album: String?
  private var albumArtist: String?
  private var composer: String?
  private var genre: String?
  private var releaseDate: String?
  private var releaseYear: Int?
  private var trackNumber: Int?
  private var trackCount: Int?
  private var discNumber: Int?
  private var discCount: Int?
  private var description: String?
  private var thumbnail: String?
  private var sourceID: String?
  private var codec: String?
  private var duration: Double?

  struct Values {
    let title: String?
    let track: String?
    let artist: String?
    let creator: String?
    let album: String?
    let albumArtist: String?
    let composer: String?
    let genre: String?
    let releaseDate: String?
    let releaseYear: Int?
    let trackNumber: Int?
    let trackCount: Int?
    let discNumber: Int?
    let discCount: Int?
    let description: String?
    let thumbnail: String?
    let sourceID: String?
    let codec: String?
    let duration: Double?
  }

  var values: Values {
    lock.withLock {
      Values(
        title: title, track: track, artist: artist, creator: creator, album: album,
        albumArtist: albumArtist, composer: composer, genre: genre, releaseDate: releaseDate,
        releaseYear: releaseYear, trackNumber: trackNumber, trackCount: trackCount,
        discNumber: discNumber, discCount: discCount, description: description,
        thumbnail: thumbnail, sourceID: sourceID, codec: codec, duration: duration
      )
    }
  }

  func consume(_ line: String) -> Bool {
    let strings: [(String, (String?) -> Void)] = [
      ("EUCRANTE_TITLE:", { self.title = $0 }),
      ("EUCRANTE_TRACK:", { self.track = $0 }),
      ("EUCRANTE_ARTIST:", { self.artist = $0 }),
      ("EUCRANTE_CREATOR:", { self.creator = $0 }),
      ("EUCRANTE_ALBUM:", { self.album = $0 }),
      ("EUCRANTE_ALBUM_ARTIST:", { self.albumArtist = $0 }),
      ("EUCRANTE_COMPOSER:", { self.composer = $0 }),
      ("EUCRANTE_GENRE:", { self.genre = $0 }),
      ("EUCRANTE_RELEASE_DATE:", { self.releaseDate = $0 }),
      ("EUCRANTE_DESCRIPTION:", { self.description = $0 }),
      ("EUCRANTE_THUMBNAIL:", { self.thumbnail = $0 }),
      ("EUCRANTE_ID:", { self.sourceID = $0 }),
      ("EUCRANTE_VCODEC:", { self.codec = $0 }),
    ]
    for (prefix, setter) in strings where line.hasPrefix(prefix) {
      let value = Self.decodeString(String(line.dropFirst(prefix.count)))
      lock.withLock { setter(value) }
      return true
    }
    let integers: [(String, (Int?) -> Void)] = [
      ("EUCRANTE_RELEASE_YEAR:", { self.releaseYear = $0 }),
      ("EUCRANTE_TRACK_NUMBER:", { self.trackNumber = $0 }),
      ("EUCRANTE_TRACK_COUNT:", { self.trackCount = $0 }),
      ("EUCRANTE_DISC_NUMBER:", { self.discNumber = $0 }),
      ("EUCRANTE_DISC_COUNT:", { self.discCount = $0 }),
    ]
    for (prefix, setter) in integers where line.hasPrefix(prefix) {
      let value = Self.decodeNumber(String(line.dropFirst(prefix.count))).map(Int.init)
      lock.withLock { setter(value) }
      return true
    }
    if line.hasPrefix("EUCRANTE_DURATION:") {
      let value = Self.decodeNumber(String(line.dropFirst("EUCRANTE_DURATION:".count)))
      lock.withLock { duration = value }
      return true
    }
    return false
  }

  private static func decodeString(_ value: String) -> String? {
    guard let data = value.data(using: .utf8),
      let decoded = try? JSONDecoder().decode(String.self, from: data),
      !decoded.isEmpty
    else { return nil }
    return decoded
  }

  private static func decodeNumber(_ value: String) -> Double? {
    guard let data = value.data(using: .utf8) else { return nil }
    if let decoded = try? JSONDecoder().decode(Double.self, from: data) { return decoded }
    return decodeString(value).flatMap(Double.init)
  }
}

extension VideoQuality {
  fileprivate var prefersWideVideoCodec: Bool {
    switch self {
    case .maximum, .p4320, .p2160, .p1440: true
    case .p1080, .p720, .p480, .p360, .p240, .p144: false
    }
  }
}
