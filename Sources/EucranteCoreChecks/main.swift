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
    try checkEndpointSecurity()
    try checkRequestEncoding()
    try checkResponseDecoding()
    try checkFilenameSafety()
    try await checkRequestToFileFlow()
    print("EucranteCoreChecks: all checks passed")
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

  private static func checkEndpointSecurity() throws {
    _ = try EndpointSecurityPolicy.validate("https://api.example/")
    _ = try EndpointSecurityPolicy.validate("http://localhost:9000/")

    do {
      _ = try EndpointSecurityPolicy.validate("http://api.example/")
      throw CheckFailure.failed("public HTTP endpoint was accepted")
    } catch is EndpointSecurityError {
      // Expected.
    }

    try require(
      !EndpointSecurityPolicy.allowsCredentials(
        to: URL(string: "http://192.168.1.25:9000/")!),
      "credentials were allowed over private HTTP"
    )
  }

  private static func checkRequestEncoding() throws {
    var preferences = DownloadPreferences()
    preferences.downloadMode = .audio
    preferences.audioBitrate = .kbps320
    let request = CobaltRequest(
      sourceURL: URL(string: "https://example.com/media")!,
      preferences: preferences
    )
    let object =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
    try require(object?["downloadMode"] as? String == "audio", "downloadMode wire value changed")
    try require(object?["audioBitrate"] as? String == "320", "audioBitrate wire value changed")
    try require(
      object?["localProcessing"] as? String == "disabled", "localProcessing default changed")
  }

  private static func checkResponseDecoding() throws {
    let tunnelJSON = Data(
      #"{"status":"tunnel","url":"https://files.example/video.mp4","filename":"video.mp4"}"#.utf8
    )
    let tunnel = try JSONDecoder().decode(CobaltResponse.self, from: tunnelJSON)
    guard case .tunnel(let transfer) = tunnel else {
      throw CheckFailure.failed("tunnel response was not discriminated")
    }
    try require(transfer.filename == "video.mp4", "tunnel filename was not decoded")

    let errorJSON = Data(
      #"{"status":"error","error":{"code":"error.api.auth.api_key.missing"}}"#.utf8
    )
    let failure = try JSONDecoder().decode(CobaltResponse.self, from: errorJSON)
    guard case .failure(let error) = failure else {
      throw CheckFailure.failed("error response was not discriminated")
    }
    try require(error.code.contains("auth"), "API error code was not decoded")
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

  private static func checkRequestToFileFlow() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]
    let session = URLSession(configuration: configuration)

    URLProtocolStub.handler = { request in
      if request.url?.host == "api.example" {
        try require(request.httpMethod == "POST", "API client did not use POST")
        try require(
          request.value(forHTTPHeaderField: "Accept") == "application/json",
          "API client omitted the JSON Accept header"
        )
        try require(
          request.value(forHTTPHeaderField: "Authorization") == "Api-Key fixture-key",
          "API client omitted credentials from a secure endpoint"
        )
        let response = HTTPURLResponse(
          url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
        let body = Data(
          #"{"status":"tunnel","url":"https://files.example/file","filename":"sample:video.mp4"}"#
            .utf8
        )
        return (response, body)
      }

      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "video/mp4"]
      )!
      return (response, Data("fixture-media".utf8))
    }

    let sourceURL = URL(string: "https://source.example/watch/1")!
    let engine = CobaltAPIClient(
      baseURL: URL(string: "https://api.example/")!,
      authentication: .apiKey("fixture-key"),
      session: session
    )
    let response = try await engine.process(CobaltRequest(sourceURL: sourceURL))
    guard case .tunnel(let transfer) = response else {
      throw CheckFailure.failed("request-to-file fixture did not return a tunnel")
    }

    let outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    defer {
      try? FileManager.default.removeItem(at: outputDirectory)
      session.invalidateAndCancel()
      URLProtocolStub.handler = nil
    }

    let saved = try await DownloadService(session: session).download(
      from: transfer.url,
      suggestedFilename: transfer.filename,
      to: outputDirectory
    )
    try require(
      saved.url.lastPathComponent == "sample-video.mp4", "saved filename was not sanitized")
    let savedData = try Data(contentsOf: saved.url)
    try require(
      savedData == Data("fixture-media".utf8),
      "saved media did not match the response body"
    )

    URLProtocolStub.handler = { request in
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
      return (response, Data(count: 2 * 1_024 * 1_024 + 1))
    }

    do {
      _ = try await engine.process(CobaltRequest(sourceURL: sourceURL))
      throw CheckFailure.failed("oversized API response was accepted")
    } catch CobaltClientError.responseTooLarge {
      // Expected.
    }
  }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler:
    (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let handler = Self.handler else {
      client?.urlProtocol(self, didFailWithError: CheckFailure.failed("missing URL fixture"))
      return
    }

    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}
