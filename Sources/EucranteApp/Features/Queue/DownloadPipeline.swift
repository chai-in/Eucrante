import EucranteCore
import Foundation

struct DownloadUpdate: Sendable {
  let state: PersistentJob.State
  var progress: Double?
  var bytesCompleted: Int64?
  var bytesExpected: Int64?
}

struct DownloadResult {
  let media: ProcessedMedia
  let metadata: MediaMetadata
  let decision: MediaDecision
}

@MainActor
struct DownloadPipeline {
  let acquirer: any LocalMediaAcquiring
  let processor: LocalMediaProcessor
  let transcoder: AppleVideoTranscoder
  let session: any YouTubeSessionStoring
  let workspace: DownloadWorkspace

  func run(
    _ job: PersistentJob,
    progress: @escaping @Sendable (DownloadUpdate) -> Void
  ) async throws -> DownloadResult {
    guard let request = job.request else { throw MediaProcessingError.missingInput }
    let destination =
      try request.destinationBookmark.map { try OutputFolderBookmark.resolve($0).url }
      ?? request.destination
    let access = destination.startAccessingSecurityScopedResource()
    defer { if access { destination.stopAccessingSecurityScopedResource() } }
    let staging = workspace.staging(for: job.id)
    try SecureCredentialFile.prepareDirectory(staging)
    defer { workspace.removeStaging(for: job.id) }
    try Task.checkCancellation()

    let acquired = try await acquire(job, in: staging, progress: progress)
    try Task.checkCancellation()
    let input: URL
    let filename: String
    let providerMetadata: MediaMetadata
    var mergeAudio: URL?
    var decisionOverride: MediaDecision?
    progress(DownloadUpdate(state: .processing, progress: 0))

    switch acquired {
    case .single(let url, let name, let metadata):
      input = url
      filename = name
      providerMetadata = metadata
    case .merge(let video, let audio, let name, let metadata):
      input = video
      mergeAudio = audio
      filename = name
      providerMetadata = metadata
    case .transcode(let video, let audio, let name, let duration, let quality, let metadata):
      input = try await transcoder.transcode(
        video: video, audio: audio, duration: duration, quality: quality,
        workingDirectory: staging,
        progress: { progress(DownloadUpdate(state: .processing, progress: $0)) })
      let info = try await processor.inspect(input)
      let durationMatches =
        duration.map { $0.isFinite && abs(info.duration - $0) <= max(1, $0 * 0.02) } ?? true
      guard ["hvc1", "hev1"].contains(info.videoCodec ?? ""),
        audio == nil || info.audioCodec != nil, durationMatches
      else {
        throw MediaProcessingError.verification(
          "The converter did not produce the requested HEVC media.")
      }
      discardIntermediates([video] + (audio.map { [$0] } ?? []), in: staging, retaining: input)
      filename = name
      providerMetadata = metadata
      decisionOverride = .transcodeHEVC
    }

    var metadata = providerMetadata.applyingUserOverrides(job.metadataOverrides)
    if job.isAudio, job.metadataOverrides?.artworkURL == nil, let artwork = metadata.artworkURL {
      if let cached = await ArtworkStore.cacheProviderArtwork(
        from: artwork, jobID: job.id, rootDirectory: workspace.artwork)
      {
        metadata.artworkURL = cached
      }
    }
    try Task.checkCancellation()
    progress(DownloadUpdate(state: .processing))
    let processingProgress: @Sendable (Double) -> Void = {
      progress(DownloadUpdate(state: $0 >= 1 ? .verifying : .processing, progress: $0))
    }
    let processed: ProcessedMedia
    if let audio = mergeAudio {
      processed = try await processor.process(
        video: input, audio: audio, preset: job.preset, suggestedFilename: filename,
        destination: destination, progress: processingProgress)
    } else {
      processed = try await processor.process(
        input, preset: decisionOverride == nil ? job.preset : .custom,
        suggestedFilename: filename, destination: destination, progress: processingProgress)
    }
    // A returned file has been committed. No fallible or cancellable work follows publication.
    return DownloadResult(
      media: processed, metadata: metadata, decision: decisionOverride ?? processed.decision)
  }

  private func discardIntermediates(_ files: [URL], in staging: URL, retaining output: URL) {
    for file in files where file.standardizedFileURL != output.standardizedFileURL {
      // Only this attempt's private files are disposable; injected/external inputs stay intact.
      guard file.deletingLastPathComponent().standardizedFileURL == staging.standardizedFileURL
      else { continue }
      try? FileManager.default.removeItem(at: file)
    }
  }

  private func acquire(
    _ job: PersistentJob,
    in staging: URL,
    progress: @escaping @Sendable (DownloadUpdate) -> Void
  ) async throws -> LocalAcquisitionResult {
    let cookie: URL?
    if SourceURLValidator.isYouTube(job.sourceURL) {
      guard await session.hasAuthenticatedSession() else {
        throw LocalAcquisitionError.authenticationRequired
      }
      try Task.checkCancellation()
      cookie = try await session.exportCookieFile(to: staging)
    } else {
      cookie = nil
    }
    defer { if let cookie { try? FileManager.default.removeItem(at: cookie) } }
    try Task.checkCancellation()
    guard let request = job.request else { throw MediaProcessingError.missingInput }
    if SourceURLValidator.isYouTube(job.sourceURL), cookie == nil {
      throw LocalAcquisitionError.authenticationRequired
    }
    progress(DownloadUpdate(state: .downloading))
    return try await acquirer.acquire(
      sourceURL: job.sourceURL, preset: job.preset,
      preferences: request.preferences, cookieFile: cookie, workingDirectory: staging,
      progress: {
        progress(
          DownloadUpdate(
            state: .downloading, progress: $0.fraction,
            bytesCompleted: $0.bytesCompleted, bytesExpected: $0.bytesExpected))
      })
  }
}
