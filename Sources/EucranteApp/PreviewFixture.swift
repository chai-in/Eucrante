#if DEBUG
  @preconcurrency import AVFoundation
  import EucranteCore
  import Foundation
  import WebKit

  @MainActor
  enum PreviewFixture {
    static func makeModel() throws -> AppModel {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "Eucrante-Preview-\(UUID().uuidString)", isDirectory: true)
      let output = root.appendingPathComponent("Downloads", isDirectory: true)
      try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
      let defaults = UserDefaults(suiteName: "app.eucrante.preview.\(UUID().uuidString)")!
      defaults.set(
        try OutputFolderBookmark.create(for: output), forKey: "downloads.output-bookmark.v1")
      let store = JobStore(fileURL: root.appendingPathComponent("jobs.json"))
      let tone = output.appendingPathComponent("Studio Sample.wav")
      try PreviewAcquirer.writeTone(to: tone)
      try store.save([
        PersistentJob(
          sourceURL: URL(string: "https://example.com/studio")!, preset: .appleMusicBest,
          state: .completed, bytesCompleted: 88_244, filename: tone.lastPathComponent,
          outputPath: tone.path,
          mediaDecision: .passthrough,
          mediaMetadata: MediaMetadata(title: "Studio Sample", artist: "Eucrante Preview")),
        PersistentJob(
          sourceURL: URL(string: "https://example.com/unavailable")!, preset: .appleVideoBest,
          state: .failed, errorMessage: "This source is unavailable. Try another link.",
          mediaMetadata: MediaMetadata(title: "Unavailable source")),
      ])
      let model = AppModel(
        defaults: defaults, localAcquirer: PreviewAcquirer(),
        youtubeSessionStore: YouTubeSessionStore(dataStore: .nonPersistent()), jobStore: store)
      model.sourceText = "https://example.com/studio-sample"
      return model
    }
  }

  private actor PreviewAcquirer: LocalMediaAcquiring, LocalMediaPreviewing {
    func toolStatus() async -> LocalToolStatus {
      LocalToolStatus(
        ready: true, downloaderVersion: "preview", runtimeVersion: "preview",
        transcoderVersion: "preview")
    }

    func preview(sourceURL: URL, cookieFile: URL?, workingDirectory: URL) async throws
      -> MediaPreview
    {
      try await Task.sleep(for: .milliseconds(350))
      return MediaPreview(
        metadata: MediaMetadata(
          title: "Studio Sample", artist: "Eucrante Preview", album: "Local Fixtures", year: 2026),
        duration: 1,
        formats: [
          MediaPreviewFormat(
            identifier: "audio", container: "m4a", videoCodec: nil, audioCodec: "mp4a",
            width: nil, height: nil, frameRate: nil, totalBitrate: 256, audioBitrate: 256,
            fileSize: 32000, approximateFileSize: nil)
        ])
    }

    func acquire(
      sourceURL: URL, preset: EucrantePreset, preferences: DownloadPreferences,
      cookieFile: URL?, workingDirectory: URL,
      progress: @escaping @Sendable (LocalAcquisitionProgress) -> Void
    ) async throws -> LocalAcquisitionResult {
      for step in 1...30 {
        try await Task.sleep(for: .milliseconds(200))
        progress(
          LocalAcquisitionProgress(
            fraction: Double(step) / 30, bytesCompleted: Int64(step * 1000), bytesExpected: 30000))
      }
      let file = workingDirectory.appendingPathComponent("sample.wav")
      try Self.writeTone(to: file)
      return .single(
        url: file, suggestedFilename: "Studio Sample.wav",
        metadata: MediaMetadata(title: "Studio Sample"))
    }

    nonisolated static func writeTone(to url: URL) throws {
      let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
      buffer.frameLength = buffer.frameCapacity
      for frame in 0..<Int(buffer.frameLength) {
        buffer.floatChannelData![0][frame] = Float(
          sin(Double(frame) * 2 * .pi * 440 / 44_100) * 0.1)
      }
      let writer = try AVAudioFile(forWriting: url, settings: format.settings)
      try writer.write(from: buffer)
    }
  }
#endif
