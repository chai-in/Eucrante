@preconcurrency import AVFoundation
import EucranteCore
import XCTest

@testable import EucranteApp

@MainActor
final class TrimTimelineTests: XCTestCase {
  func testZoomKeepsViewportBoundedAndMappingReversible() {
    var timeline = TrimTimelineGeometry(duration: 7200)
    timeline.setZoom(100, around: 7190)
    XCTAssertEqual(timeline.upper, 7200)
    XCTAssertGreaterThanOrEqual(timeline.origin, 0)
    XCTAssertEqual(timeline.time(at: timeline.fraction(at: 7160)), 7160, accuracy: 0.001)
    timeline.setZoom(9999, around: 0)
    XCTAssertEqual(timeline.zoom, 200)
    XCTAssertEqual(timeline.origin, 0)
    timeline.setZoom(1, around: 1000)
    XCTAssertEqual(timeline.span, 7200)
    XCTAssertEqual(timeline.origin, 0)
  }

  func testTimestampRoundTripAndInvalidSelection() throws {
    for value in [0.0, 0.125, 59.999, 60, 3661.25, 7200] {
      XCTAssertEqual(
        try XCTUnwrap(MediaTimeRange.parse(TrimTimelineGeometry.timestamp(value))), value,
        accuracy: 0.001)
    }
    XCTAssertNil(TrimTimelineGeometry.bounds(start: "30", end: "10", duration: 60))
    XCTAssertNil(TrimTimelineGeometry.bounds(start: "0", end: "61", duration: 60))
    XCTAssertNil(TrimTimelineGeometry.bounds(start: "NaN", end: "", duration: 60))
    XCTAssertEqual(TrimTimelineGeometry.bounds(start: "", end: "", duration: 60)?.1, 60)
  }

  func testSelectionPlaybackSeeksAndStopsAtEndAndResetReleasesPlayer() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("tone.wav")
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 88200))
    buffer.frameLength = buffer.frameCapacity
    for frame in 0..<Int(buffer.frameLength) {
      buffer.floatChannelData![0][frame] = Float(sin(Double(frame) * 2 * .pi * 440 / 44100) * 0.1)
    }
    do {
      let writer = try AVAudioFile(forWriting: url, settings: format.settings)
      try writer.write(from: buffer)
    }
    let model = TrimPreviewModel(
      session: SiteSessionStore(), workspace: DownloadWorkspace(root: root))
    defer { model.reset() }
    model.installPlayer(AVPlayerItem(url: url), hasVideo: false)
    model.player?.isMuted = true
    try await wait { model.playbackReady }
    model.playSelection(start: 0.5, end: 0.8)
    try await wait { model.playing }
    try await wait { !model.playing }
    XCTAssertEqual(model.player?.currentTime().seconds ?? 0, 0.8, accuracy: 0.06)
    XCTAssertEqual(model.playhead, 0.8, accuracy: 0.06)
    model.playSelection(start: 0, end: 1.8)
    model.reset()
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertNil(model.player)
    XCTAssertFalse(model.playing)
    XCTAssertFalse(model.playbackReady)
  }

  private func wait(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(6)
    while !condition() && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    XCTAssertTrue(condition())
  }
}
