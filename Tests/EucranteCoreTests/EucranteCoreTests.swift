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

  private func decode(_ json: String) throws -> CobaltResponse {
    try JSONDecoder().decode(CobaltResponse.self, from: Data(json.utf8))
  }
}
