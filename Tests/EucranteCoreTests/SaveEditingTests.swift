@preconcurrency import AVFoundation
import AudioToolbox
import XCTest

@testable import EucranteCore

@MainActor
final class SaveEditingTests: XCTestCase {
  func testTimeParsingAndUntrustedRanges() throws {
    XCTAssertEqual(try MediaTimeRange.parse("1:02.5"), 62.5)
    XCTAssertEqual(try MediaTimeRange.parse("1:02:03"), 3723)
    for invalid in ["1:60", "-1", "nan", "inf", "1::2", "1.2:30", "1:2:3:4"] {
      XCTAssertThrowsError(try MediaTimeRange.parse(invalid), invalid)
    }
    XCTAssertThrowsError(try MediaTimeRange(start: 2, end: 1))
    XCTAssertThrowsError(try MediaTimeRange(start: 2, end: 10).duration(in: 5))
    let decoded = try JSONDecoder().decode(
      MediaTimeRange.self, from: Data(#"{"start":-3,"end":1}"#.utf8))
    XCTAssertThrowsError(try decoded.duration(in: 5))
  }

  func testPagePayloadBoundaryAndDuplicateRejection() throws {
    func url(_ object: [String: Any]) throws -> URL {
      let json = try JSONSerialization.data(withJSONObject: object)
      var parts = URLComponents(string: "eucrante://page")!
      parts.queryItems = [
        URLQueryItem(name: "payload", value: String(decoding: json, as: UTF8.self))
      ]
      return parts.url!
    }
    let item = ["url": "https://youtube.com/watch?v=OAS-STPdWbc", "title": "Song"]
    let valid: [String: Any] = [
      "page": "https://youtube.com", "title": "Page", "items": [item], "truncated": false,
    ]
    XCTAssertEqual(try PageMediaSelection.decode(url(valid)).items.count, 1)
    for items in [
      [item, item], [["url": "file:///etc/passwd", "title": "bad"]],
      Array(repeating: item, count: 101),
    ] {
      var invalid = valid
      invalid["items"] = items
      XCTAssertThrowsError(try PageMediaSelection.decode(url(invalid)))
    }
  }

  func testTrimEmbedsMetadataAndPreservesDurationAfterPublication() async throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try await tone(root, seconds: 4)
    let processor = LocalMediaProcessor()
    let edited = try await processor.prepareForSave(
      source,
      timeRange: MediaTimeRange(start: 1, end: 2.5),
      metadata: MediaMetadata(title: "Edited title", artist: "Test Artist"), directory: root)
    let result = try await processor.process(
      edited, preset: .appleMusicBest,
      suggestedFilename: "clip.m4a", destination: root.appendingPathComponent("output"))
    XCTAssertEqual(result.output.duration, 1.5, accuracy: 0.1)
    let metadata = try await AVURLAsset(url: result.url).load(.commonMetadata)
    let title = metadata.first { $0.commonKey == .commonKeyTitle }
    let titleValue = try await title?.load(.stringValue)
    XCTAssertEqual(titleValue, "Edited title")
    let audio = try AVAudioFile(forReading: result.url)
    XCTAssertEqual(Double(audio.length) / audio.processingFormat.sampleRate, 1.5, accuracy: 0.1)
  }

  func testMalformedAACContainerIsRepairedWithoutChangingPackets() async throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try await tone(root, seconds: 4)
    let fragmented = root.appendingPathComponent("fragmented.m4a")
    let ffmpeg = LocalMediaAcquirer.ToolPaths.discover().ffmpeg
    guard FileManager.default.isExecutableFile(atPath: ffmpeg.path) else {
      throw XCTSkip("Install the pinned local tools to build a fragmented AAC regression fixture.")
    }
    _ = try await LocalProcessRunner().run(
      executable: ffmpeg,
      arguments: [
        "-hide_banner", "-loglevel", "error", "-i", source.path, "-c", "copy", "-movflags",
        "+frag_keyframe+empty_moov", "-f", "mp4", fragmented.path,
      ],
      environment: ProcessInfo.processInfo.environment, onLine: { _ in })
    var bytes = try Data(contentsOf: fragmented)
    // Reproduce the downloaded file: AAC packets are intact, but the movie's
    // sample durations and movie/track lengths are doubled.
    func get(_ offset: Int) -> UInt32 {
      bytes[offset..<offset + 4].reduce(0) { ($0 << 8) | UInt32($1) }
    }
    func set(_ offset: Int, _ value: UInt32) {
      bytes.replaceSubrange(
        offset..<offset + 4, with: (0..<4).map { UInt8((value >> (24 - $0 * 8)) & 255) })
    }
    func visit(_ start: Int, _ end: Int) {
      var offset = start
      while offset + 8 <= end {
        let shortSize = get(offset)
        let extended = shortSize == 1
        let size =
          extended ? Int(UInt64(get(offset + 8)) << 32 | UInt64(get(offset + 12))) : Int(shortSize)
        guard size >= 8, offset + size <= end else { return }
        let type = String(decoding: bytes[offset + 4..<offset + 8], as: UTF8.self)
        let base = offset + (extended ? 16 : 8)
        if ["moov", "trak", "mdia", "minf", "stbl", "edts"].contains(type) {
          visit(base, offset + size)
        }
        if ["mvhd", "mdhd"].contains(type), bytes[base] == 0 { set(base + 16, get(base + 12) * 4) }
        if type == "tkhd", bytes[base] == 0 { set(base + 20, 4000) }
        offset += size
      }
    }
    visit(0, bytes.count)
    let malformed = root.appendingPathComponent("malformed.m4a")
    try bytes.write(to: malformed)
    let before = try await AVURLAsset(url: malformed).load(.duration).seconds
    XCTAssertGreaterThan(before, 7.9)
    let repaired = try await AudioContainerRepair.repairIfNeeded(malformed, in: root)
    XCTAssertNotEqual(malformed, repaired)
    let after = try await AVURLAsset(url: repaired).load(.duration).seconds
    XCTAssertEqual(after, 4, accuracy: 0.1)
    XCTAssertEqual(try packets(source), try packets(repaired))
    XCTAssertEqual(try Data(contentsOf: malformed), bytes, "Original file is never rewritten")
  }

  func testSilenceFailsBeforePublishing() async throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("silence.wav")
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100)!
    buffer.frameLength = buffer.frameCapacity
    for i in 0..<44100 { buffer.floatChannelData![0][i] = 0 }
    do {
      let writer = try AVAudioFile(forWriting: url, settings: format.settings)
      try writer.write(from: buffer)
    }
    let destination = root.appendingPathComponent("output")
    do {
      _ = try await LocalMediaProcessor().process(
        url, preset: .appleMusicBest, suggestedFilename: "silent.wav", destination: destination)
      XCTFail("Silent output was published")
    } catch { XCTAssertTrue(error.localizedDescription.contains("silent")) }
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), [])
  }

  private func directory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func tone(_ root: URL, seconds: Int) async throws -> URL {
    let url = root.appendingPathComponent("tone.wav")
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    do {
      let writer = try AVAudioFile(forWriting: url, settings: format.settings)
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format, frameCapacity: AVAudioFrameCount(44100 * seconds))!
      buffer.frameLength = buffer.frameCapacity
      for i in 0..<Int(buffer.frameLength) {
        buffer.floatChannelData![0][i] = Float(sin(Double(i) * 2 * .pi * 440 / 44100) * 0.2)
      }
      try writer.write(from: buffer)
    }
    return try await LocalMediaProcessor().process(
      url, preset: .appleMusicEfficient, suggestedFilename: "tone.m4a",
      destination: root.appendingPathComponent("encoded")
    ).url
  }

  private func packets(_ url: URL) throws -> Data {
    var file: AudioFileID?
    XCTAssertEqual(AudioFileOpenURL(url as CFURL, .readPermission, 0, &file), noErr)
    let opened = try XCTUnwrap(file)
    defer { AudioFileClose(opened) }
    var result = Data()
    var position: Int64 = 0
    while true {
      var bytes = [UInt8](repeating: 0, count: 65536)
      var descriptions = [AudioStreamPacketDescription](repeating: .init(), count: 64)
      var count: UInt32 = 64
      var size: UInt32 = 65536
      let status = AudioFileReadPacketData(
        opened, false, &size, &descriptions, position, &count, &bytes)
      XCTAssertTrue(status == noErr || status == kAudioFileEndOfFileError)
      if count == 0 { break }
      result.append(contentsOf: bytes.prefix(Int(size)))
      position += Int64(count)
    }
    return result
  }
}
