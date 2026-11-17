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
  func previews(
    sourceURLs: [URL], cookieFile: URL?, workingDirectory: URL,
    receive: @escaping @Sendable (URL, Result<MediaPreview, LocalAcquisitionError>) async -> Void
  ) async throws
}

extension LocalMediaPreviewing {
  public func previews(
    sourceURLs: [URL], cookieFile: URL?, workingDirectory: URL,
    receive: @escaping @Sendable (URL, Result<MediaPreview, LocalAcquisitionError>) async -> Void
  ) async throws {
    for source in sourceURLs {
      try Task.checkCancellation()
      do {
        let value = try await preview(
          sourceURL: source, cookieFile: cookieFile, workingDirectory: workingDirectory)
        await receive(source, .success(value))
      } catch {
        try Task.checkCancellation()
        await receive(source, .failure(error as? LocalAcquisitionError ?? .processFailed(-1)))
      }
    }
  }
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

  let tools: ToolPaths
  private let fileManager: FileManager
  private let toolCheckTimeout: Duration
  private let runner = LocalProcessRunner()

  public init(
    tools: ToolPaths = .discover(),
    fileManager: FileManager = .default,
    toolCheckTimeout: Duration = .seconds(30)
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
        kinds: [
          .audio(maximumBitrate: preset == .appleMusicEfficient ? 256 : nil, allowCombined: true)
        ],
        cookieFile: cookieFile,
        videoQuality: preferences.videoQuality,
        workingDirectory: workingDirectory,
        progress: progress
      )[0]
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

    let runs: [DownloadRun]
    do {
      runs = try await download(
        sourceURL: sourceURL,
        kinds: mute
          ? [.video]
          : [.video, .audio(maximumBitrate: preset == .appleVideoEfficient ? 256 : nil)],
        cookieFile: cookieFile, videoQuality: preferences.videoQuality,
        workingDirectory: workingDirectory, progress: progress)
      if !mute, runs.count == 1 {
        // Comma selection is best-effort: a provider may return only one match.
        // Reuse it only when the downloaded file actually contains both tracks.
        let run = runs[0]
        let media = try await LocalMediaProcessor().inspect(run.url)
        guard media.videoCodec != nil, media.audioCodec != nil else {
          throw LocalAcquisitionError.formatUnavailable
        }
        return .single(
          url: run.url,
          suggestedFilename: preferences.filenameStyle.filename(
            title: run.title, creator: run.creator,
            sourceID: run.sourceID, pathExtension: "mp4"), metadata: run.metadata)
      }
    } catch LocalAcquisitionError.formatUnavailable where !mute {
      // Many social-video sites expose one MP4 with audio, without separate tracks.
      let fallback = workingDirectory.appendingPathComponent("combined")
      let run = try await download(
        sourceURL: sourceURL, kinds: [.combined],
        cookieFile: cookieFile, videoQuality: preferences.videoQuality,
        workingDirectory: fallback, progress: progress)[0]
      return .single(
        url: run.url,
        suggestedFilename: preferences.filenameStyle.filename(
          title: run.title, creator: run.creator,
          sourceID: run.sourceID, pathExtension: "mp4"), metadata: run.metadata)
    }
    let video = runs[0]
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

    let audio = runs[1]
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
      "--print", Self.previewTemplate,
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

  public func previews(
    sourceURLs: [URL], cookieFile: URL?, workingDirectory: URL,
    receive: @escaping @Sendable (URL, Result<MediaPreview, LocalAcquisitionError>) async -> Void
  ) async throws {
    guard !sourceURLs.isEmpty else { return }
    guard toolsAreExecutable else { throw LocalAcquisitionError.toolsMissing }
    try LocalProcessRunner.prepareRestrictedEnvironment(homeDirectory: workingDirectory)
    // One helper per small batch reuses its extractor/player caches. --print before_dl runs
    // only after full format extraction, so flat playlist entries never count as verified.
    let template = "{\"source\":%(original_url)j,\"document\":" + Self.previewTemplate + "}"
    var arguments = [
      "--ignore-config", "--no-playlist", "--no-warnings", "--skip-download",
      "--ignore-errors", "--socket-timeout", "10", "--retries", "1", "--extractor-retries", "1",
      "--print", template, "--js-runtimes", "deno:\(tools.deno.path)",
    ]
    if let cookieFile { arguments += ["--cookies", cookieFile.path] }
    arguments += sourceURLs.map(\.absoluteString)
    let (events, continuation) = AsyncStream<(URL, Result<MediaPreview, LocalAcquisitionError>)>
      .makeStream(bufferingPolicy: .bufferingOldest(16))
    // The pipe already bounds individual lines; a batch contains at most eight URLs.
    let allowed = Set(sourceURLs)
    let reader = Task { () -> Set<URL> in
      var received: Set<URL> = []
      for await (source, result) in events {
        guard allowed.contains(source), received.insert(source).inserted else { continue }
        await receive(source, result)
      }
      return received
    }
    var failure: LocalAcquisitionError = .previewUnavailable
    do {
      _ = try await runner.run(
        executable: tools.ytDLP, arguments: arguments,
        environment: LocalProcessRunner.restrictedEnvironment(homeDirectory: workingDirectory),
        onLine: { line in
          if line.hasPrefix("{\"source\":"), let data = line.data(using: .utf8),
            let envelope = try? JSONDecoder().decode(PreviewEnvelope.self, from: data),
            allowed.contains(envelope.source)
          {
            continuation.yield(
              (envelope.source, .success(envelope.document.preview(sourceURL: envelope.source))))
          } else if line.hasPrefix("ERROR: ") {
            // YouTube reports an exact video ID in errors. Attribute only that documented
            // prefix; other extractors use the individual fallback below. Raw diagnostics
            // and cookie values never enter the event stream or app state.
            for source in sourceURLs where SourceURLValidator.isYouTube(source) {
              let id = URLComponents(url: source, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "v" })?.value
              if let id, !id.isEmpty, line.contains("[youtube] \(id):") {
                continuation.yield(
                  (source, .failure(Self.processError(status: 1, diagnostic: line))))
              }
            }
          }
        })
    } catch {
      failure = error as? LocalAcquisitionError ?? .processFailed(-1)
    }
    continuation.finish()
    let received = await reader.value
    try Task.checkCancellation()
    for source in sourceURLs where !received.contains(source) {
      // A batch's stderr cannot reliably attribute a provider error to a URL. Inspect only
      // missing items individually so login/network/unsupported diagnostics stay accurate.
      do {
        let value = try await preview(
          sourceURL: source, cookieFile: cookieFile, workingDirectory: workingDirectory)
        await receive(source, .success(value))
      } catch {
        try Task.checkCancellation()
        await receive(source, .failure(error as? LocalAcquisitionError ?? failure))
      }
    }
  }

  // Print only the fields used by the UI. Signed media URLs, fragment lists, subtitles,
  // and provider response bodies never need to cross the helper pipe or enter Swift memory.
  static let previewTemplate =
    "{\"metadata\":%(.{id,title,track,artist,creator,uploader,channel,album,album_artist,composer,genre,description,release_date,release_year,upload_date,track_number,track_count,disc_number,disc_count,thumbnail,duration})j,"
    + "\"formats\":%(formats.:.{format_id,ext,vcodec,acodec,width,height,fps,tbr,abr,filesize,filesize_approx})j}"

  private enum DownloadKind {
    case video
    case combined
    case audio(maximumBitrate: Int?, allowCombined: Bool = false)

    func formatSelector(videoQuality: VideoQuality) -> String {
      switch self {
      case .video:
        return LocalMediaAcquirer.videoFormatSelector(videoQuality: videoQuality)
      case .combined:
        let height = videoQuality == .maximum ? "" : "[height<=\(videoQuality.rawValue)]"
        // `best` already selects a combined stream. Some extractors omit codec fields;
        // filtering on those fields incorrectly rejects their valid MP4s.
        return "best[ext=mp4]\(height)"
      case .audio(let maximumBitrate, let allowCombined):
        let bestAppleAudio =
          "bestaudio[acodec^=mp4a][ext=m4a]/bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]"
        let combinedFallback = allowCombined ? "/best[ext=mp4][acodec^=?mp4a]" : ""
        guard let maximumBitrate else { return bestAppleAudio + combinedFallback }
        return
          "bestaudio[acodec^=mp4a][ext=m4a][abr<=\(maximumBitrate)]/"
          + "bestaudio[ext=m4a][abr<=\(maximumBitrate)]/"
          + "bestaudio[acodec^=mp4a][abr<=\(maximumBitrate)]/"
          + bestAppleAudio + combinedFallback
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
    kinds: [DownloadKind],
    cookieFile: URL?,
    videoQuality: VideoQuality,
    workingDirectory: URL,
    progress: @escaping @Sendable (LocalAcquisitionProgress) -> Void
  ) async throws -> [DownloadRun] {
    try Task.checkCancellation()
    var arguments = [
      "--ignore-config",
      "--no-playlist",
      "--newline",
      "--progress",
      "--progress-delta", "0.25",
      "--continue",
      "--js-runtimes", "deno:\(tools.deno.path)",
      // Comma selection downloads separate tracks using one extraction and helper launch.
      "--format",
      kinds.map { "(\($0.formatSelector(videoQuality: videoQuality)))" }.joined(separator: ","),
      "--output", workingDirectory.appendingPathComponent("media-%(autonumber)02d.%(ext)s").path,
      "--print", "before_dl:EUCRANTE_BEGIN:%(autonumber)d",
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
      "--print", "after_move:EUCRANTE_END:%(autonumber)d",
      "--progress-template",
      "download:EUCRANTE_PROGRESS:%(progress.downloaded_bytes)s:%(progress.total_bytes)s:%(progress.total_bytes_estimate)s",
    ]
    if let cookieFile {
      arguments.append(contentsOf: ["--cookies", cookieFile.path])
    }
    arguments.append(sourceURL.absoluteString)

    let records = LockedDownloadRecords()
    try LocalProcessRunner.prepareRestrictedEnvironment(
      homeDirectory: workingDirectory, fileManager: fileManager)
    let environment = LocalProcessRunner.restrictedEnvironment(homeDirectory: workingDirectory)
    _ = try await runner.run(
      executable: tools.ytDLP,
      arguments: arguments,
      environment: environment
    ) { line in
      if let parsed = Self.parseProgress(line) {
        let lower = Double(records.values.count) / Double(kinds.count)
        let width = 1 / Double(kinds.count)
        progress(
          LocalAcquisitionProgress(
            fraction: parsed.fraction.map { lower + ($0 * width) },
            bytesCompleted: parsed.completed,
            bytesExpected: parsed.expected
          ))
      } else {
        records.consume(line)
      }
    }
    let values = records.values
    guard values.count == kinds.count || (kinds.count == 2 && values.count == 1) else {
      throw LocalAcquisitionError.outputMissing
    }
    return try values.enumerated().map { index, metadata in
      try downloadRun(
        values: metadata, prefix: String(format: "media-%02d", index + 1),
        sourceURL: sourceURL, workingDirectory: workingDirectory)
    }
  }

  private func downloadRun(
    values: LockedMetadata.Values, prefix: String, sourceURL: URL, workingDirectory: URL
  ) throws -> DownloadRun {
    guard
      let output = try Self.outputFile(
        prefix: prefix,
        in: workingDirectory,
        fileManager: fileManager
      )
    else {
      throw LocalAcquisitionError.outputMissing
    }
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
    if [
      "sign in to confirm", "login required", "login is required", "log in to", "sign in to",
      "cookies are no longer valid", "cookies have expired", "authentication required",
      "login_required", "requires authentication", "use --cookies", "pass --cookies",
    ].contains(where: normalized.contains) {
      return .authenticationRequired
    }
    if normalized.contains("unsupported url") || normalized.contains("no suitable extractor") {
      return .unsupportedSite
    }
    if normalized.contains("drm") { return .protectedMedia }
    if normalized.contains("http error 429") || normalized.contains("too many requests") {
      return .rateLimited
    }
    if normalized.contains("http error 403") || normalized.contains("forbidden") {
      return .accessDenied
    }
    if [
      "timed out", "unable to download webpage", "network is unreachable", "name resolution",
      "nodename nor servname",
    ].contains(where: normalized.contains) {
      return .networkUnavailable
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
  case outputTooLarge
  case unsupportedSite
  case protectedMedia
  case networkUnavailable
  case rateLimited

  public var errorDescription: String? {
    switch self {
    case .toolsMissing:
      "Eucrante's local media tools are missing or damaged. Reinstall the app."
    case .processFailed:
      "The website could not provide usable media for this link. Check that it is a single playable item; the site may have changed."
    case .authenticationRequired:
      "This website requires a fresh sign-in for this link. Reconnect its private session in Eucrante."
    case .accessDenied:
      "The website refused access (403). This may be a site restriction or an expired media link; it does not by itself prove a login problem."
    case .formatUnavailable:
      "This link does not currently expose media that matches the selected output. Try another preset."
    case .outputMissing:
      "The provider returned no usable media file."
    case .previewUnavailable:
      "Eucrante could not read preview details for this link. You can still try saving it."
    case .unsupportedSite:
      "This link is not supported by the media engine. Try the direct page for a single video or audio item."
    case .protectedMedia:
      "This media is protected by DRM and cannot be saved by Eucrante."
    case .networkUnavailable:
      "The website could not be reached. Check your connection and try again."
    case .rateLimited:
      "The website is limiting requests. Wait a little before checking this site again."
    case .outputTooLarge:
      "The provider returned more metadata than Eucrante can safely process. Try a link to a single item."
    }
  }
}

private struct PreviewEnvelope: Decodable {
  let source: URL
  let document: PreviewDocument
}

private struct PreviewDocument: Decodable {
  let metadata: PreviewMetadataDocument
  let formats: [PreviewFormatDocument]

  func preview(sourceURL: URL) -> MediaPreview {
    metadata.preview(sourceURL: sourceURL, formats: formats)
  }
}

private struct PreviewMetadataDocument: Decodable {
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

  enum CodingKeys: String, CodingKey {
    case id, title, track, artist, creator, uploader, channel, album, composer, genre, description
    case thumbnail, duration
    case albumArtist = "album_artist"
    case releaseDate = "release_date"
    case releaseYear = "release_year"
    case uploadDate = "upload_date"
    case trackNumber = "track_number"
    case trackCount = "track_count"
    case discNumber = "disc_number"
    case discCount = "disc_count"
  }

  func preview(sourceURL: URL, formats: [PreviewFormatDocument]) -> MediaPreview {
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

private final class LockedDownloadRecords: @unchecked Sendable {
  private let lock = NSLock()
  private var current = LockedMetadata()
  private var completed: [LockedMetadata.Values] = []

  var values: [LockedMetadata.Values] { lock.withLock { completed } }

  func consume(_ line: String) {
    lock.withLock {
      if line.hasPrefix("EUCRANTE_BEGIN:") {
        current = LockedMetadata()
      } else if line.hasPrefix("EUCRANTE_END:") {
        // A save selects at most two tracks, even if a helper produces unexpected output.
        if completed.count < 3 { completed.append(current.values) }
      } else {
        _ = current.consume(line)
      }
    }
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
      let value = Self.decodeNumber(String(line.dropFirst(prefix.count))).flatMap {
        Int(exactly: $0)
      }
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
