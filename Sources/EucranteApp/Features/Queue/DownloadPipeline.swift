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
  let session: any SiteSessionStoring
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
    var input: URL
    var filename: String
    let providerMetadata: MediaMetadata
    var decisionOverride: MediaDecision?
    progress(DownloadUpdate(state: .processing, progress: 0))

    switch acquired {
    case .single(let url, let name, let metadata):
      input = url
      filename = name
      providerMetadata = metadata
    case .merge(let video, let audio, let name, let metadata):
      let repairedAudio = try await AudioContainerRepair.repairIfNeeded(audio, in: staging)
      input = try await processor.merge(
        video: video, audio: repairedAudio, filename: name, workingDirectory: staging)
      discardIntermediates([video, audio], in: staging, retaining: input)
      filename = name
      providerMetadata = metadata
    case .transcode(let video, let audio, let name, let duration, let quality, let metadata):
      let repairedAudio: URL?
      if let audio {
        repairedAudio = try await AudioContainerRepair.repairIfNeeded(audio, in: staging)
      } else {
        repairedAudio = nil
      }
      input = try await transcoder.transcode(
        video: video, audio: repairedAudio, duration: duration, quality: quality,
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

    if job.isAudio {
      let audio = try await processor.extractAudioIfNeeded(input, in: staging)
      if audio != input {
        input = audio
        filename = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent + ".m4a"
      }
    }
    var metadata = providerMetadata.applyingUserOverrides(job.metadataOverrides)
    if job.isAudio, job.metadataOverrides?.artworkURL == nil, let artwork = metadata.artworkURL {
      if let cached = await ArtworkStore.cacheProviderArtwork(
        from: artwork, jobID: job.id, style: request.coverStyle ?? .original,
        removeBlackBars: request.removeBlackBars ?? true, rootDirectory: workspace.artwork)
      {
        metadata.artworkURL = cached
      } else if request.coverStyle != nil && request.coverStyle != .original {
        throw ArtworkStoreError.invalidImage
      }
    }
    try Task.checkCancellation()
    input = try await AudioContainerRepair.repairIfNeeded(input, in: staging)
    if let expected = request.expectedDuration, expected.isFinite, expected > 0 {
      let actual = try await processor.inspect(input).duration
      guard abs(actual - expected) <= max(1, expected * 0.02) else {
        throw MediaProcessingError.verification(
          "The downloaded duration does not match the selected item. Refresh its preview and try again."
        )
      }
    }
    input = try await processor.prepareForSave(
      input, timeRange: request.timeRange, metadata: job.isAudio ? metadata : nil,
      directory: staging)
    progress(DownloadUpdate(state: .processing))
    let processed = try await processor.process(
      input, preset: decisionOverride == nil ? job.preset : .custom,
      suggestedFilename: filename, destination: destination,
      progress: {
        progress(DownloadUpdate(state: $0 >= 1 ? .verifying : .processing, progress: $0))
      })
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
    let cookie = try await session.exportCookieFile(for: job.sourceURL, to: staging)
    defer { if let cookie { try? FileManager.default.removeItem(at: cookie) } }
    try Task.checkCancellation()
    guard let request = job.request else { throw MediaProcessingError.missingInput }
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
