import Foundation

// Compile with ArtworkStore.swift (without its EucranteCore import) and SecureCredentialFile.swift.
@main
enum ArtworkDownloadMeasurement {
  static func main() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FixtureImageProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let start = ContinuousClock.now
    for _ in 0..<5 {
      let data = try await ArtworkStore.download(
        from: URL(string: "https://example.test/artwork")!, session: session)
      precondition(data.count == 4 * 1_024 * 1_024 && data.allSatisfy { $0 == 42 })
    }
    print("5 bounded 4 MiB downloads: \(start.duration(to: .now))")
  }
}

private final class FixtureImageProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    client?.urlProtocol(
      self,
      didReceive: HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "image/png", "Content-Length": "4194304"])!,
      cacheStoragePolicy: .notAllowed)
    let chunk = Data(repeating: 42, count: 65_536)
    for _ in 0..<64 { client?.urlProtocol(self, didLoad: chunk) }
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
