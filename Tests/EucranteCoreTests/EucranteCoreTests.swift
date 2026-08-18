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

  func testEndpointSecurityPolicy() throws {
    XCTAssertEqual(
      try EndpointSecurityPolicy.validate("https://cobalt.example.com/").host,
      "cobalt.example.com"
    )
    XCTAssertNoThrow(try EndpointSecurityPolicy.validate("http://localhost:9000/"))
    XCTAssertNoThrow(try EndpointSecurityPolicy.validate("http://192.168.1.25:9000/"))
    XCTAssertNoThrow(try EndpointSecurityPolicy.validate("http://[fd00::1]:9000/"))
    XCTAssertThrowsError(try EndpointSecurityPolicy.validate("http://cobalt.example.com/"))
    XCTAssertThrowsError(try EndpointSecurityPolicy.validate("http://fc.example.com/"))
    XCTAssertThrowsError(try EndpointSecurityPolicy.validate("https://user:secret@example.com/"))

    XCTAssertTrue(
      EndpointSecurityPolicy.allowsCredentials(to: URL(string: "https://example.com/")!))
    XCTAssertTrue(
      EndpointSecurityPolicy.allowsCredentials(to: URL(string: "http://127.0.0.1:9000/")!))
    XCTAssertFalse(
      EndpointSecurityPolicy.allowsCredentials(to: URL(string: "http://192.168.1.25:9000/")!))
    XCTAssertFalse(
      EndpointSecurityPolicy.allowsConnection(to: URL(string: "http://cobalt.example.com/")!))
  }

  func testClientRejectsCredentialsBeforeSendingToPrivateHTTP() async throws {
    let client = CobaltAPIClient(
      baseURL: URL(string: "http://192.168.1.25:9000/")!,
      authentication: .apiKey("fixture-secret")
    )

    do {
      _ = try await client.instanceInfo()
      XCTFail("Expected insecure credential transport to be rejected")
    } catch {
      XCTAssertEqual(error as? CobaltClientError, .insecureAuthenticationEndpoint)
    }
  }

  func testClientRejectsPublicHTTPWithoutCredentials() async throws {
    let client = CobaltAPIClient(baseURL: URL(string: "http://cobalt.example.com/")!)

    do {
      _ = try await client.instanceInfo()
      XCTFail("Expected a public HTTP endpoint to be rejected")
    } catch {
      XCTAssertEqual(error as? CobaltClientError, .insecureEndpoint)
    }
  }

  func testRequestUsesDocumentedWireValues() throws {
    var preferences = DownloadPreferences()
    preferences.downloadMode = .audio
    preferences.audioBitrate = .kbps320
    preferences.videoQuality = .maximum
    preferences.filenameStyle = .nerdy

    let request = CobaltRequest(
      sourceURL: URL(string: "https://example.com/media")!,
      preferences: preferences
    )
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
    )

    XCTAssertEqual(object["downloadMode"] as? String, "audio")
    XCTAssertEqual(object["audioBitrate"] as? String, "320")
    XCTAssertEqual(object["videoQuality"] as? String, "max")
    XCTAssertEqual(object["filenameStyle"] as? String, "nerdy")
    XCTAssertEqual(object["localProcessing"] as? String, "disabled")
  }

  func testDecodesTunnelResponse() throws {
    let response = try decode(
      """
      {"status":"tunnel","url":"https://files.example/video.mp4","filename":"A video.mp4"}
      """
    )

    guard case .tunnel(let transfer) = response else {
      return XCTFail("Expected a tunnel response")
    }
    XCTAssertEqual(transfer.filename, "A video.mp4")
    XCTAssertEqual(transfer.url.host, "files.example")
  }

  func testDecodesPickerResponse() throws {
    let response = try decode(
      """
      {
        "status":"picker",
        "audio":"https://files.example/audio.mp3",
        "audioFilename":"audio.mp3",
        "picker":[
          {"type":"photo","url":"https://files.example/1.jpg","thumb":"https://files.example/1-thumb.jpg"},
          {"type":"video","url":"https://files.example/2.mp4"}
        ]
      }
      """
    )

    guard case .picker(let picker) = response else {
      return XCTFail("Expected a picker response")
    }
    XCTAssertEqual(picker.picker.count, 2)
    XCTAssertEqual(picker.picker.first?.type, .photo)
    XCTAssertEqual(picker.audioFilename, "audio.mp3")
  }

  func testDecodesLocalProcessingResponse() throws {
    let response = try decode(
      """
      {
        "status":"local-processing",
        "type":"merge",
        "service":"youtube",
        "tunnel":["https://files.example/video","https://files.example/audio"],
        "output":{
          "type":"video/mp4",
          "filename":"merged.mp4",
          "metadata":{"title":"Example"},
          "subtitles":false
        },
        "audio":{"copy":true,"format":"m4a","bitrate":"128"},
        "isHLS":false
      }
      """
    )

    guard case .localProcessing(let local) = response else {
      return XCTFail("Expected a local-processing response")
    }
    XCTAssertEqual(local.type, "merge")
    XCTAssertEqual(local.tunnel.count, 2)
    XCTAssertEqual(local.output.metadata?["title"], "Example")
  }

  func testDecodesAPIError() throws {
    let response = try decode(
      """
      {"status":"error","error":{"code":"error.api.auth.api_key.missing","context":{"service":"youtube","limit":120}}}
      """
    )

    guard case .failure(let error) = response else {
      return XCTFail("Expected an API error response")
    }
    XCTAssertEqual(error.code, "error.api.auth.api_key.missing")
    XCTAssertEqual(error.context?.service, "youtube")
    XCTAssertEqual(error.context?.limit, 120)
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

  func testOneClickPresetsOverrideCustomPreferences() {
    var custom = DownloadPreferences()
    custom.downloadMode = .mute
    custom.videoQuality = .p360
    custom.audioBitrate = .kbps64

    let music = EucrantePreset.appleMusicEfficient.requestPreferences(from: custom)
    XCTAssertEqual(music.downloadMode, .audio)
    XCTAssertEqual(music.videoQuality, .maximum)
    XCTAssertEqual(music.audioBitrate, .kbps256)
    XCTAssertEqual(music.localProcessing, .preferred)

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
    XCTAssertLessThanOrEqual(processed.output.sampleRate ?? .infinity, 44_101)
  }

  func testMultipartOutputUploadResumesCompletedParts() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("EucranteUploadTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("large.mp4")
    try Data(count: 8 * 1_024 * 1_024 + 1).write(to: file)

    MockURLProtocol.reset()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let jobID = UUID()
    let resume = EucranteMultipartState(
      uploadID: "upload-fixture",
      fileSize: 8 * 1_024 * 1_024 + 1,
      partSize: 8 * 1_024 * 1_024,
      parts: [EucranteMultipartPart(partNumber: 1, etag: "etag-one")],
      bytesCompleted: 8 * 1_024 * 1_024
    )

    let result = try await EucranteAPIClient(
      baseURL: URL(string: "https://eucrante.example/")!,
      session: session
    ).uploadOutput(
      jobID: jobID,
      fileURL: file,
      slot: "verified-output.mp4",
      contentType: "video/mp4",
      resumeState: resume
    )

    XCTAssertEqual(result.size, resume.fileSize)
    let requests = MockURLProtocol.recordedRequests()
    XCTAssertEqual(requests.filter { $0.httpMethod == "PUT" }.count, 1)
    XCTAssertTrue(requests.contains { $0.url?.path.hasSuffix("/multipart/parts/2") == true })
    XCTAssertFalse(
      requests.contains {
        $0.httpMethod == "PUT" && $0.url?.path.hasSuffix("/multipart/parts/1") == true
      })
    XCTAssertTrue(requests.contains { $0.url?.path.hasSuffix("/multipart/complete") == true })
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

  private func decode(_ json: String) throws -> CobaltResponse {
    try JSONDecoder().decode(CobaltResponse.self, from: Data(json.utf8))
  }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var requests: [URLRequest] = []

  static func reset() {
    lock.withLock { requests = [] }
  }

  static func recordedRequests() -> [URLRequest] {
    lock.withLock { requests }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lock.withLock { Self.requests.append(request) }
    let path = request.url?.path ?? ""
    let body: String
    if path.hasSuffix("/multipart/parts/2") {
      body = #"{"partNumber":2,"etag":"etag-two"}"#
    } else if path.hasSuffix("/multipart/complete") {
      body = #"{"slot":"verified-output.mp4","size":8388609,"etag":"etag-final"}"#
    } else {
      body = #"{"uploadId":"upload-fixture","key":"jobs/fixture/output"}"#
    }
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: path.hasSuffix("/multipart/complete") ? 200 : 201,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
