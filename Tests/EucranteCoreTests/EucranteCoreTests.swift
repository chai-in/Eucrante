@preconcurrency import AVFoundation
import XCTest

@testable import EucranteCore

final class EucranteCoreTests: XCTestCase {
  func testSourceURLValidation() throws {
    let url = try SourceURLValidator.validate("  https://example.com/watch?v=1  ")
    XCTAssertEqual(url.host, "example.com")
    XCTAssertThrowsError(try SourceURLValidator.validate("file:///tmp/video.mp4"))
    XCTAssertThrowsError(try SourceURLValidator.validate("example.com/video"))
  }

  func testFilenameSanitizerRemovesTraversalAndControlCharacters() {
    let sanitized = FilenameSanitizer.sanitize("../../bad:name/video.mp4")
    XCTAssertFalse(sanitized.contains("/"))
    XCTAssertFalse(sanitized.contains("\\"))
    XCTAssertFalse(sanitized.contains(":"))
    XCTAssertEqual(FilenameSanitizer.sanitize("\u{0000}\n"), "download")
    XCTAssertLessThanOrEqual(
      FilenameSanitizer.sanitize(String(repeating: "a", count: 300) + ".mp4").count, 180)
  }

  func testEveryFilenameStyleHasAUsefulPreview() {
    for style in FilenameStyle.allCases {
      XCTAssertFalse(style.displayName.isEmpty)
      XCTAssertFalse(style.sampleFilename.isEmpty)
      XCTAssertTrue(style.sampleFilename.hasSuffix(".mp4"))
      XCTAssertFalse(style.explanation.isEmpty)
    }
    XCTAssertEqual(FilenameStyle.basic.sampleFilename, "Midnight Drive.mp4")
    XCTAssertNotEqual(FilenameStyle.classic.sampleFilename, FilenameStyle.pretty.sampleFilename)
  }

  func testFilenameStylesDriveTheSavedFilename() {
    XCTAssertEqual(
      FilenameStyle.classic.filename(
        title: "Midnight Drive", creator: "Aurora Vale", sourceID: "dQ8k2Lm7",
        pathExtension: "mp4"),
      "Midnight Drive - Aurora Vale.mp4"
    )
    XCTAssertEqual(
      FilenameStyle.pretty.filename(
        title: "Midnight Drive", creator: "Aurora Vale", sourceID: "dQ8k2Lm7",
        pathExtension: "mp4"),
      "Midnight Drive • Aurora Vale.mp4"
    )
    XCTAssertEqual(
      FilenameStyle.basic.filename(
        title: "Midnight Drive", creator: "Aurora Vale", sourceID: "dQ8k2Lm7",
        pathExtension: "mp4"),
      "Midnight Drive.mp4"
    )
    XCTAssertEqual(
      FilenameStyle.nerdy.filename(
        title: "Midnight Drive", creator: "Aurora Vale", sourceID: "dQ8k2Lm7",
        pathExtension: "mp4"),
      "Midnight Drive [dQ8k2Lm7].mp4"
    )
    XCTAssertEqual(
      FilenameStyle.classic.filename(
        title: "Midnight Drive", creator: nil, sourceID: nil, pathExtension: "m4a"),
      "Midnight Drive.m4a"
    )
  }

  func testOneClickPresetsOverrideCustomPreferences() {
    var custom = DownloadPreferences()
    custom.downloadMode = .mute
    custom.videoQuality = .p360
    custom.audioBitrate = .kbps64

    let music = EucrantePreset.appleMusicEfficient.requestPreferences(from: custom)
    XCTAssertEqual(music.downloadMode, .audio)
    XCTAssertEqual(music.videoQuality, .maximum)
    XCTAssertEqual(music.audioBitrate, .kbps256)

    let video = EucrantePreset.appleVideoBest.requestPreferences(from: custom)
    XCTAssertEqual(video.downloadMode, .automatic)
    XCTAssertEqual(video.videoQuality, .maximum)
    XCTAssertEqual(video.youtubeVideoContainer, .mp4)
  }

  func testJobStoreRoundTrip() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("EucranteTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = JobStore(fileURL: root.appendingPathComponent("jobs.json"))
    let expected = PersistentJob(
      sourceURL: URL(string: "https://example.com/media")!,
      preset: .appleMusicEfficient,
      state: .completed,
      filename: "Example.m4a",
      outputPath: "/tmp/Example.m4a"
    )

    try await store.save([expected])
    let restored = try await store.load()
    XCTAssertEqual(restored.count, 1)
    XCTAssertEqual(restored.first?.id, expected.id)
    XCTAssertEqual(restored.first?.sourceURL, expected.sourceURL)
    XCTAssertEqual(restored.first?.preset, expected.preset)
    XCTAssertEqual(restored.first?.state, expected.state)
    XCTAssertEqual(restored.first?.filename, expected.filename)
    XCTAssertEqual(restored.first?.outputPath, expected.outputPath)
    try await store.removeAll()
    let empty = try await store.load()
    XCTAssertEqual(empty, [])
  }

  func testEfficientMusicPresetCreatesVerifiedAAC() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("EucranteMediaTests-\(UUID().uuidString)", isDirectory: true)
    let inputDirectory = root.appendingPathComponent("input", isDirectory: true)
    let outputDirectory = root.appendingPathComponent("output", isDirectory: true)
    try FileManager.default.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let input = inputDirectory.appendingPathComponent("tone.wav")
    try makeTone(at: input)
    let processed: ProcessedMedia
    do {
      processed = try await LocalMediaProcessor().process(
        input,
        preset: .appleMusicEfficient,
        suggestedFilename: "Test Tone.wav",
        destination: outputDirectory,
        progress: { _ in }
      )
    } catch MediaProcessingError.codecUnavailable {
      throw XCTSkip("The active macOS beta does not expose the system AAC encoder.")
    }

    XCTAssertEqual(processed.decision, .transcodeAAC)
    XCTAssertEqual(processed.url.pathExtension, "m4a")
    XCTAssertNotNil(processed.output.audioCodec)
    XCTAssertGreaterThan(processed.output.fileSize, 0)
  }

  private func makeTone(at url: URL) throws {
    let sampleRate = 44_100.0
    let format = try XCTUnwrap(
      AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2))
    let frames = AVAudioFrameCount(sampleRate / 4)
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
    buffer.frameLength = frames
    for channel in 0..<Int(format.channelCount) {
      guard let samples = buffer.floatChannelData?[channel] else { continue }
      for frame in 0..<Int(frames) {
        samples[frame] = Float(sin(2 * .pi * 440 * Double(frame) / sampleRate) * 0.15)
      }
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
  }
}
