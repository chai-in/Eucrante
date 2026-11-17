import AppKit
import Foundation
import ImageIO
import XCTest

@testable import EucranteApp

final class ArtworkEfficiencyTests: XCTestCase {
  func testArtworkDownsamplesLargeInputsWithoutUpscalingSmallImages() throws {
    for width in [32, 8192] {
      let bitmap = try XCTUnwrap(
        NSBitmapImageRep(
          bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: 32, bitsPerSample: 8,
          samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB,
          bytesPerRow: 0, bitsPerPixel: 0))
      let sourceData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      let normalized = try XCTUnwrap(ArtworkNormalizer.jpegData(from: sourceData))
      let source = try XCTUnwrap(CGImageSourceCreateWithData(normalized as CFData, nil))
      let properties = try XCTUnwrap(
        CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
      XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, min(width, 2048))
      XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, width > 2048 ? 8 : 32)
      XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.jpeg")
    }
  }

  func testArtworkStreamingAcceptsValidDataAndRejectsOversizedOrInvalidResponses() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ArtworkResponseProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let data = try await ArtworkStore.download(
      from: URL(string: "https://example.test/valid")!, session: session)
    XCTAssertEqual(data, Data([1, 2, 3]))
    for path in ["large-header", "large-body", "not-image", "failed", "empty"] {
      do {
        _ = try await ArtworkStore.download(
          from: URL(string: "https://example.test/\(path)")!, session: session)
        XCTFail("Expected \(path) to be rejected")
      } catch {
        XCTAssertTrue(error is ArtworkStoreError)
      }
    }
    do {
      _ = try await ArtworkStore.download(
        from: URL(string: "http://example.test/valid")!, session: session)
      XCTFail("Expected HTTP to be rejected")
    } catch { XCTAssertTrue(error is ArtworkStoreError) }
  }
}

private final class ArtworkResponseProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let url = request.url!
    let path = url.lastPathComponent
    var headers = ["Content-Type": path == "not-image" ? "text/plain" : "image/png"]
    if path == "large-header" {
      headers["Content-Length"] = String(ArtworkStore.maximumSourceBytes + 1)
    }
    let response = HTTPURLResponse(
      url: url, statusCode: path == "failed" ? 500 : 200,
      httpVersion: "HTTP/1.1", headerFields: headers)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    if path == "large-body" {
      client?.urlProtocol(
        self, didLoad: Data(repeating: 1, count: ArtworkStore.maximumSourceBytes + 1))
    } else if path != "empty" {
      client?.urlProtocol(self, didLoad: Data([1, 2, 3]))
    }
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
