@preconcurrency import AVFoundation
import XCTest

@testable import EucranteCore

final class EucranteCoreTests: XCTestCase {
  func testSourceURLValidation() throws {
    let url = try SourceURLValidator.validate("  https://example.com/watch?v=1  ")
    XCTAssertEqual(url.host, "example.com")
    XCTAssertThrowsError(try SourceURLValidator.validate("file:///tmp/video.mp4"))
    XCTAssertThrowsError(try SourceURLValidator.validate("example.com/video"))
    XCTAssertThrowsError(try SourceURLValidator.validate("https://user:secret@example.com/video"))
    XCTAssertThrowsError(try SourceURLValidator.validate(String(repeating: "a", count: 8_193)))
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

    let music = EucrantePreset.appleMusicEfficient.requestPreferences(from: custom)
    XCTAssertEqual(music.downloadMode, .audio)
    XCTAssertEqual(music.videoQuality, .maximum)

    let video = EucrantePreset.appleVideoBest.requestPreferences(from: custom)
    XCTAssertEqual(video.downloadMode, .automatic)
    XCTAssertEqual(video.videoQuality, .maximum)
  }

  func testVideoSelectorPreservesH264FastPathThrough1080p() {
    let selector = LocalMediaAcquirer.videoFormatSelector(videoQuality: .p1080)
    XCTAssertTrue(selector.hasPrefix("bestvideo[vcodec^=avc1]"))
    XCTAssertFalse(selector.contains("vp9"))
    XCTAssertTrue(selector.contains("height<=1080"))
  }

  func testVideoSelectorPrefersVP9For1440pAndAbove() {
    for quality in [VideoQuality.p1440, .p2160, .p4320, .maximum] {
      let selector = LocalMediaAcquirer.videoFormatSelector(videoQuality: quality)
      XCTAssertTrue(selector.hasPrefix("bestvideo[vcodec^=vp9]"))
      XCTAssertTrue(selector.contains("bestvideo[vcodec^=avc1]"))
    }
    XCTAssertTrue(
      LocalMediaAcquirer.videoFormatSelector(videoQuality: .p2160).contains("height<=2160"))
  }

  func testWideVideoConversionUsesAppleHardwareHEVCWithoutGPLCodec() {
    let arguments = AppleVideoTranscoder.arguments(
      video: URL(fileURLWithPath: "/tmp/source.webm"),
      audio: URL(fileURLWithPath: "/tmp/audio.m4a"),
      output: URL(fileURLWithPath: "/tmp/output.mp4"),
      quality: .best
    )
    XCTAssertTrue(arguments.contains("hevc_videotoolbox"))
    XCTAssertTrue(arguments.contains("hvc1"))
    XCTAssertTrue(arguments.contains("copy"))
    XCTAssertEqual(arguments[arguments.firstIndex(of: "-allow_sw")! + 1], "1")
    XCTAssertFalse(arguments.contains("libx265"))
    XCTAssertEqual(arguments.last, "/tmp/output.mp4")
  }

  func testWideVideoConversionProgressParsing() {
    let parsed = AppleVideoTranscoder.parseProgressTime("out_time_us=1250000")
    XCTAssertNotNil(parsed)
    XCTAssertEqual(parsed ?? 0, 1.25, accuracy: 0.0001)
    XCTAssertNil(AppleVideoTranscoder.parseProgressTime("progress=continue"))
    XCTAssertEqual(AppleVideoTranscoder.parseProgressTime("out_time_ms=2500000") ?? 0, 2.5)
  }

  func testDownloaderProgressParsingUsesExactOrEstimatedTotal() throws {
    let exact = try XCTUnwrap(LocalMediaAcquirer.parseProgress("EUCRANTE_PROGRESS:25:100:"))
    XCTAssertEqual(exact.fraction ?? 0, 0.25)
    XCTAssertEqual(exact.completed, 25)
    XCTAssertEqual(exact.expected, 100)

    let estimated = try XCTUnwrap(
      LocalMediaAcquirer.parseProgress("EUCRANTE_PROGRESS:150::200"))
    XCTAssertEqual(estimated.fraction ?? 0, 0.75)
    XCTAssertEqual(estimated.expected, 200)

    let clamped = try XCTUnwrap(
      LocalMediaAcquirer.parseProgress("EUCRANTE_PROGRESS:300:200:"))
    XCTAssertEqual(clamped.fraction, 1)
    XCTAssertNil(LocalMediaAcquirer.parseProgress("[download] 25%"))
    XCTAssertNil(LocalMediaAcquirer.parseProgress("EUCRANTE_PROGRESS:1:2"))
  }

  func testDownloaderErrorsAreActionableWithoutLeakingDiagnostics() {
    XCTAssertEqual(
      LocalMediaAcquirer.processError(status: 1, diagnostic: "Sign in to confirm you're not a bot"),
      .authenticationRequired
    )
    XCTAssertEqual(
      LocalMediaAcquirer.processError(status: 1, diagnostic: "HTTP Error 403: Forbidden"),
      .accessDenied
    )
    XCTAssertEqual(
      LocalMediaAcquirer.processError(
        status: 1,
        diagnostic: "Requested format is not available"
      ),
      .formatUnavailable
    )
    XCTAssertEqual(
      LocalMediaAcquirer.processError(status: 17, diagnostic: "provider detail"),
      .processFailed(17)
    )
    XCTAssertFalse(
      LocalMediaAcquirer.processError(status: 17, diagnostic: "private-token")
        .localizedDescription.contains("private-token")
    )
  }

  func testDownloaderOutputSelectionRejectsEmptyFilesAndSymlinks() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("EucranteOutputTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data().write(to: root.appendingPathComponent("audio.m4a"))
    XCTAssertNil(try LocalMediaAcquirer.outputFile(prefix: "audio", in: root))

    let target = root.appendingPathComponent("target.m4a")
    try Data("media".utf8).write(to: target)
    let link = root.appendingPathComponent("audio.mp4")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    XCTAssertNil(try LocalMediaAcquirer.outputFile(prefix: "audio", in: root))

    let output = root.appendingPathComponent("audio.webm")
    try Data("media".utf8).write(to: output)
    XCTAssertEqual(
      try LocalMediaAcquirer.outputFile(prefix: "audio", in: root)?.resolvingSymlinksInPath(),
      output.resolvingSymlinksInPath()
    )
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
    let mode = try XCTUnwrap(
      FileManager.default.attributesOfItem(
        atPath: root.appendingPathComponent("jobs.json").path
      )[.posixPermissions] as? NSNumber
    ).intValue
    XCTAssertEqual(mode & 0o777, 0o600)
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

  func testLegacyPreferencesDecodeWhileIgnoringRemovedCobaltFields() throws {
    let legacy = Data(
      #"{"downloadMode":"audio","videoQuality":"720","filenameStyle":"pretty","alwaysProxy":true,"subtitleLanguage":"en","youtubeVideoCodec":"vp9","audioBitrate":"64"}"#
        .utf8
    )
    let preferences = try JSONDecoder().decode(DownloadPreferences.self, from: legacy)
    XCTAssertEqual(preferences.downloadMode, .audio)
    XCTAssertEqual(preferences.videoQuality, .p720)
    XCTAssertEqual(preferences.filenameStyle, .pretty)
  }

  func testUniqueDestinationAvoidsExistingAndReservedNames() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("EucranteDestinationTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let original = root.appendingPathComponent("Track.m4a")
    try Data("one".utf8).write(to: original)
    let second = FileDestinationResolver.uniqueDestination(for: "Track.m4a", in: root)
    XCTAssertEqual(second.lastPathComponent, "Track 2.m4a")
    let third = FileDestinationResolver.uniqueDestination(
      for: "Track.m4a",
      in: root,
      reservedPaths: [second.path]
    )
    XCTAssertEqual(third.lastPathComponent, "Track 3.m4a")
  }

  func testSecureCredentialFileUsesPrivatePermissionsBeforeWriting() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("EucranteCredentialTests-\(UUID().uuidString)", isDirectory: true)
    let directory = root.appendingPathComponent("job", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let contents = Data("private-session".utf8)
    let file = try SecureCredentialFile.write(
      contents,
      named: ".credentials",
      to: directory
    )

    XCTAssertEqual(try Data(contentsOf: file), contents)
    let directoryMode = try XCTUnwrap(
      FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
    ).intValue
    let fileMode = try XCTUnwrap(
      FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
    ).intValue
    XCTAssertEqual(directoryMode & 0o777, 0o700)
    XCTAssertEqual(fileMode & 0o777, 0o600)
  }

  func testSecureCredentialDirectoryRepairsExistingPermissions() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o755]
    )

    try SecureCredentialFile.prepareDirectory(root)

    let attributes = try FileManager.default.attributesOfItem(atPath: root.path)
    XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, NSNumber(value: 0o700))
  }

  func testSecureCredentialFileRejectsPathComponents() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("EucranteCredentialTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    XCTAssertThrowsError(
      try SecureCredentialFile.write(Data(), named: "../credentials", to: root)
    ) { error in
      XCTAssertEqual(error as? SecureCredentialFileError, .invalidFilename)
    }
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

  func testConcurrentSavesReserveDistinctDestinationNames() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("EucranteConcurrentTests-\(UUID().uuidString)", isDirectory: true)
    let inputDirectory = root.appendingPathComponent("input", isDirectory: true)
    let outputDirectory = root.appendingPathComponent("output", isDirectory: true)
    try FileManager.default.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let input = inputDirectory.appendingPathComponent("tone.wav")
    try makeTone(at: input)
    let processor = LocalMediaProcessor()
    do {
      async let first = processor.process(
        input,
        preset: .appleMusicEfficient,
        suggestedFilename: "Same Track.wav",
        destination: outputDirectory
      )
      async let second = processor.process(
        input,
        preset: .appleMusicEfficient,
        suggestedFilename: "Same Track.wav",
        destination: outputDirectory
      )
      let (firstResult, secondResult) = try await (first, second)
      let outputs = [firstResult.url, secondResult.url]
      XCTAssertEqual(Set(outputs.map(\.lastPathComponent)).count, 2)
      XCTAssertTrue(outputs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    } catch MediaProcessingError.codecUnavailable {
      throw XCTSkip("The active macOS beta does not expose the system AAC encoder.")
    }
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
