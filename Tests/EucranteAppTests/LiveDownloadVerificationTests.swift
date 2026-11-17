import AVFoundation
import EucranteCore
import XCTest

@testable import EucranteApp

/// Explicit opt-in against one existing job; never changes the user's history or output files.
@MainActor
final class LiveDownloadVerificationTests: XCTestCase {
  func testLiveTimelineFramesAndAccessDiagnosis() async throws {
    guard ProcessInfo.processInfo.environment["EUCRANTE_VERIFY_TIMELINE"] == "1" else {
      throw XCTSkip("Set EUCRANTE_VERIFY_TIMELINE=1 for the public preview streaming check.")
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = TrimPreviewModel(
      session: VerificationSession(), workspace: DownloadWorkspace(root: root))
    defer {
      model.reset()
      try? FileManager.default.removeItem(at: root)
    }
    model.load(
      source: URL(string: "https://www.youtube.com/watch?v=V_w8fhtkTBY")!, audioOnly: false)
    try await wait(seconds: 45) { !model.loading }
    XCTAssertNil(model.message)
    model.showFrames(at: [0, 50, 100, 150, 200])
    try await wait(seconds: 30) { model.frames.count == 5 && model.frames.allSatisfy { $0 != nil } }
    if model.websiteAttention {
      XCTAssertFalse(model.playbackReady)
      XCTAssertNotNil(model.playbackMessage)
      print(
        "Live YouTube timeline: 5 frames loaded; denied media stream was diagnosed before playback."
      )
      return
    }
    try await wait(seconds: 25) { model.playbackReady }
    XCTAssertNil(model.playbackMessage)
    model.player?.isMuted = true
    model.playSelection(start: 10, end: 12)
    try await wait(seconds: 15) { model.playing }
    try await wait(seconds: 25) { !model.playing }
    XCTAssertEqual(model.player?.currentTime().seconds ?? 0, 12, accuracy: 0.15)
    print("Live timeline: 5 storyboard frames loaded; selection playback ended at 12 seconds.")
  }

  func testLivePublicMP4SelectionPlayback() async throws {
    guard ProcessInfo.processInfo.environment["EUCRANTE_VERIFY_TIMELINE"] == "1" else {
      throw XCTSkip("Set EUCRANTE_VERIFY_TIMELINE=1 for the public streaming test.")
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = TrimPreviewModel(
      session: VerificationSession(), workspace: DownloadWorkspace(root: root))
    defer { model.reset() }
    model.installPlayer(
      AVPlayerItem(
        url: URL(
          string: "https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4")!),
      hasVideo: true)
    model.player?.isMuted = true
    try await wait(seconds: 25) { model.playbackReady }
    model.playSelection(start: 1, end: 2)
    try await wait(seconds: 15) { model.playing }
    try await wait(seconds: 25) { !model.playing }
    XCTAssertEqual(model.player?.currentTime().seconds ?? 0, 2, accuracy: 0.15)
    print("Public MP4 stream: selection playback stopped at 2 seconds.")
  }

  private func wait(seconds: Double, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
    guard condition() else {
      throw MediaProcessingError.verification("Timed out waiting for live preview state.")
    }
  }

  func testSelectedJobThroughRealPipeline() async throws {
    guard let value = ProcessInfo.processInfo.environment["EUCRANTE_VERIFY_JOB"],
      let id = UUID(uuidString: value)
    else { throw XCTSkip("Set EUCRANTE_VERIFY_JOB to explicitly verify one existing job.") }
    let original = try XCTUnwrap(JobStore().load().first { $0.id == id })
    let request = try XCTUnwrap(original.request)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "Eucrante-Verify-\(UUID())")
    try SecureCredentialFile.prepareDirectory(root)
    defer { try? FileManager.default.removeItem(at: root) }
    let destination = root.appendingPathComponent("output")
    try SecureCredentialFile.prepareDirectory(destination)
    let job = PersistentJob(
      sourceURL: original.sourceURL, preset: original.preset,
      request: SaveRequest(
        preferences: request.preferences, destination: destination,
        timeRange: request.timeRange, expectedDuration: request.expectedDuration),
      metadataOverrides: original.metadataOverrides)
    let pipeline = DownloadPipeline(
      acquirer: LocalMediaAcquirer(), processor: LocalMediaProcessor(),
      transcoder: AppleVideoTranscoder(), session: VerificationSession(),
      workspace: DownloadWorkspace(root: root))
    let result = try await pipeline.run(job, progress: { _ in })
    XCTAssertTrue(FileManager.default.fileExists(atPath: result.media.url.path))
    XCTAssertNotNil(result.media.output.videoCodec)
    XCTAssertNotNil(result.media.output.audioCodec)
    XCTAssertGreaterThan(result.media.output.duration, 0)
    print(
      "Verified saved media: \(result.media.output.width ?? 0)x\(result.media.output.height ?? 0), "
        + "\(result.media.output.videoCodec ?? "unknown") + \(result.media.output.audioCodec ?? "unknown"), "
        + "\(result.media.output.duration) seconds")
  }
}

@MainActor
private final class VerificationSession: SiteSessionStoring {
  func hasSavedCookies(for source: URL) async -> Bool { false }
  func exportCookieFile(for source: URL, to directory: URL) async throws -> URL? { nil }
  func clear(for source: URL) async {}
}
