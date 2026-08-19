import EucranteCore
import Foundation

enum CheckFailure: Error, CustomStringConvertible {
  case failed(String)

  var description: String {
    switch self {
    case .failed(let message): message
    }
  }
}

@main
struct EucranteCoreChecks {
  static func main() async throws {
    try checkURLValidation()
    try checkFilenameSafety()
    if ProcessInfo.processInfo.environment["EUCRANTE_CHECK_TOOLS"] == "1" {
      let status = await LocalMediaAcquirer().toolStatus()
      print(
        "Local tools: \(status.downloaderVersion ?? "unknown"), "
          + "\(status.runtimeVersion ?? "unknown"), \(status.transcoderVersion ?? "unknown")"
      )
      try require(status.ready, "local tools failed their executable launch checks")
    }
    if let value = ProcessInfo.processInfo.environment["EUCRANTE_E2E_URL"],
      let sourceURL = URL(string: value)
    {
      if ProcessInfo.processInfo.environment["EUCRANTE_E2E_AUDIO"] == "1" {
        try await checkLocalAudioFlow(sourceURL: sourceURL)
      } else {
        try await checkLocalMediaFlow(sourceURL: sourceURL)
      }
    }
    if let path = ProcessInfo.processInfo.environment["EUCRANTE_INSPECT_FILE"] {
      let info = try await LocalMediaProcessor().inspect(URL(fileURLWithPath: path))
      print(
        "Local inspection: \(info.width ?? 0)x\(info.height ?? 0), "
          + "video=\(info.videoCodec ?? "none"), audio=\(info.audioCodec ?? "none")"
      )
    }
    if let path = ProcessInfo.processInfo.environment["EUCRANTE_PROCESS_FILE"] {
      try await checkAppleVideoConversion(input: URL(fileURLWithPath: path))
    }
    print("EucranteCoreChecks: all checks passed")
  }

  private static func checkLocalAudioFlow(sourceURL: URL) async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(
      "eucrante-audio-e2e-\(UUID().uuidString)", isDirectory: true)
    let staging = root.appendingPathComponent("staging", isDirectory: true)
    let destination = root.appendingPathComponent("output", isDirectory: true)
    try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }

    let cookieFile = ProcessInfo.processInfo.environment["EUCRANTE_E2E_COOKIE_FILE"]
      .map(URL.init(fileURLWithPath:))
    let preset = EucrantePreset.appleMusicEfficient
    let preferences = preset.requestPreferences(from: DownloadPreferences())
    let acquirer = LocalMediaAcquirer()
    let acquired = try await acquirer.acquire(
      sourceURL: sourceURL,
      preset: preset,
      preferences: preferences,
      cookieFile: cookieFile,
      workingDirectory: staging,
      progress: { _ in }
    )
    guard case .single(let input, let filename) = acquired else {
      throw CheckFailure.failed("audio acquisition returned an unexpected result")
    }
    let processed = try await LocalMediaProcessor().process(
      input,
      preset: preset,
      suggestedFilename: filename,
      destination: destination
    )
    try require(processed.output.fileSize > 0, "finished local audio was empty")
    try require(processed.output.audioCodec != nil, "finished local audio had no audio track")
    try require(processed.output.videoCodec == nil, "audio-only output contained video")
    print(
      "Local audio E2E: \(processed.output.audioCodec ?? "unknown"), "
        + "\(processed.output.fileSize) bytes, \(processed.decision.displayName), "
        + "filename=\(processed.url.lastPathComponent)"
    )
  }

  private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure.failed(message) }
  }

  private static func checkURLValidation() throws {
    let url = try SourceURLValidator.validate(" https://example.com/watch?v=1 ")
    try require(url.host == "example.com", "URL host was not preserved")

    do {
      _ = try SourceURLValidator.validate("file:///tmp/media.mp4")
      throw CheckFailure.failed("file URL was accepted")
    } catch is SourceURLValidationError {
      // Expected.
    }
  }

  private static func checkFilenameSafety() throws {
    let filename = FilenameSanitizer.sanitize("../../bad:name/video.mp4")
    try require(!filename.contains("/"), "filename retained a slash")
    try require(!filename.contains("\\"), "filename retained a backslash")
    try require(!filename.contains(":"), "filename retained a colon")
    try require(
      FilenameSanitizer.sanitize("\u{0000}\n") == "download", "empty filename fallback changed")
    try require(
      FilenameSanitizer.sanitize(String(repeating: "a", count: 300) + ".mp4").count <= 180,
      "filename length cap failed"
    )
  }

  private static func checkLocalMediaFlow(sourceURL: URL) async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(
      "eucrante-e2e-\(UUID().uuidString)", isDirectory: true)
    let staging = root.appendingPathComponent("staging", isDirectory: true)
    let destination = root.appendingPathComponent("output", isDirectory: true)
    try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }

    let cookieFile = ProcessInfo.processInfo.environment["EUCRANTE_E2E_COOKIE_FILE"]
      .map(URL.init(fileURLWithPath:))
    let acquirer = LocalMediaAcquirer()
    let status = await acquirer.toolStatus()
    try require(status.ready, "local tools were not ready")
    var preferences = DownloadPreferences()
    if ProcessInfo.processInfo.environment["EUCRANTE_E2E_4K"] == "1" {
      preferences.videoQuality = .maximum
    }

    let acquired = try await acquirer.acquire(
      sourceURL: sourceURL,
      preset: .appleVideoBest,
      preferences: preferences,
      cookieFile: cookieFile,
      workingDirectory: staging,
      progress: { _ in }
    )
    let processor = LocalMediaProcessor()
    let processed: ProcessedMedia
    switch acquired {
    case .merge(let video, let audio, let filename):
      let merged = try await processor.merge(
        video: video,
        audio: audio,
        filename: filename,
        workingDirectory: staging
      )
      processed = try await processor.process(
        merged,
        preset: .appleVideoBest,
        suggestedFilename: filename,
        destination: destination
      )
    case .transcode(let video, let audio, let filename, let duration, let quality):
      let converted = try await AppleVideoTranscoder().transcode(
        video: video,
        audio: audio,
        duration: duration,
        quality: quality,
        workingDirectory: staging
      )
      processed = try await processor.process(
        converted,
        preset: .custom,
        suggestedFilename: filename,
        destination: destination
      )
    case .single:
      throw CheckFailure.failed("video acquisition returned an unexpected result")
    }
    try require(processed.output.fileSize > 0, "finished local media was empty")
    try require(processed.output.videoCodec != nil, "finished local media had no video")
    try require(processed.output.audioCodec != nil, "finished local media had no audio")
    if ProcessInfo.processInfo.environment["EUCRANTE_E2E_4K"] == "1" {
      try require(
        max(processed.output.width ?? 0, processed.output.height ?? 0) >= 3_840,
        "4K flow did not preserve 4K resolution"
      )
      try require(
        ["hvc1", "hev1"].contains(processed.output.videoCodec?.lowercased() ?? ""),
        "4K flow did not produce Apple-compatible HEVC"
      )
    }
    print(
      "Local E2E: \(processed.output.width ?? 0)x\(processed.output.height ?? 0), "
        + "\(processed.output.fileSize) bytes, \(processed.decision.displayName), "
        + "filename=\(processed.url.lastPathComponent)"
    )
  }

  private static func checkAppleVideoConversion(input: URL) async throws {
    let destination = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eucrante-conversion-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: destination) }
    let result = try await LocalMediaProcessor().process(
      input,
      preset: .appleVideoBest,
      suggestedFilename: "conversion-check.mp4",
      destination: destination
    )
    print(
      "Local conversion: \(result.output.width ?? 0)x\(result.output.height ?? 0), "
        + "video=\(result.output.videoCodec ?? "none"), \(result.output.fileSize) bytes"
    )
  }
}
