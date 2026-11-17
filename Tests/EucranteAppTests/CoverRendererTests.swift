import AppKit
import EucranteCore
import XCTest

@testable import EucranteApp

final class CoverRendererTests: XCTestCase {
  func testSquareTreatmentsPreserveArtworkAndGradientUsesLocalEdgeColours() throws {
    let image = try makeImage(width: 120, height: 60) { x, _ in
      x < 60 ? [240, 40, 30] : [20, 90, 230]
    }
    let original = try XCTUnwrap(CoverRenderer.rgba(image))
    for style in [CoverStyle.white, .black, .sampled, .edgeGradient] {
      let result = try XCTUnwrap(CoverRenderer.render(image, style: style, removeBlackBars: false))
      XCTAssertEqual(result.width, 120)
      XCTAssertEqual(result.height, 120)
      let pixels = try XCTUnwrap(CoverRenderer.rgba(result))
      for y in 0..<60 {
        for x in 0..<120 {
          for c in 0..<3 {
            XCTAssertEqual(pixels[((y + 30) * 120 + x) * 4 + c], original[(y * 120 + x) * 4 + c])
          }
        }
      }
      if style == .white { XCTAssertEqual(Array(pixels.prefix(3)), [255, 255, 255]) }
      if style == .black { XCTAssertEqual(Array(pixels.prefix(3)), [0, 0, 0]) }
      if style == .edgeGradient {
        XCTAssertGreaterThan(pixels[10 * 4], pixels[10 * 4 + 2])
        XCTAssertGreaterThan(pixels[110 * 4 + 2], pixels[110 * 4])
      }
    }
  }

  func testPortraitAndLetterboxDetectionAreConservative() throws {
    let bars = try makeImage(width: 100, height: 80) { _, y in
      y < 8 || y >= 72 ? [0, 0, 0] : [30, 120, 230]
    }
    XCTAssertEqual(CoverRenderer.cropLetterbox(bars).height, 64)
    let darkArt = try makeImage(width: 100, height: 80) { _, _ in [0, 0, 0] }
    XCTAssertEqual(CoverRenderer.cropLetterbox(darkArt).height, 80)
    let portrait = try makeImage(width: 60, height: 100) { _, y in
      y < 50 ? [200, 80, 20] : [20, 100, 200]
    }
    let result = try XCTUnwrap(
      CoverRenderer.render(portrait, style: .edgeGradient, removeBlackBars: false))
    XCTAssertEqual(result.width, result.height)
    let original = try XCTUnwrap(
      CoverRenderer.render(portrait, style: .original, removeBlackBars: true))
    XCTAssertEqual(original.width, 60)
    XCTAssertEqual(original.height, 100)
  }

  private func makeImage(width: Int, height: Int, pixel: (Int, Int) -> [UInt8]) throws -> CGImage {
    var data = Data()
    for y in 0..<height { for x in 0..<width { data.append(contentsOf: pixel(x, y) + [255]) } }
    let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
    return try XCTUnwrap(
      CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
  }
}
