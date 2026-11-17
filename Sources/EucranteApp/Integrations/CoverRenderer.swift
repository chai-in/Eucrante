import CoreGraphics
import EucranteCore
import Foundation

/// Extends only the missing square border; source pixels are never blurred or stretched.
enum CoverRenderer {
  static func render(_ image: CGImage, style: CoverStyle, removeBlackBars: Bool) -> CGImage? {
    guard style != .original else { return image }
    let source = removeBlackBars ? cropLetterbox(image) : image
    let width = source.width
    let height = source.height
    let side = max(width, height)
    guard let pixels = rgba(source), side > 0 else { return nil }
    let left = (side - width) / 2
    let top = (side - height) / 2
    let horizontal = width >= height
    var average = [Double](repeating: 0, count: 3)
    var count = 0.0
    for y in stride(from: 0, to: height, by: max(1, height / 64)) {
      for x in stride(from: 0, to: width, by: max(1, width / 64)) {
        let offset = (y * width + x) * 4
        if max(pixels[offset], pixels[offset + 1], pixels[offset + 2]) < 20 { continue }
        for channel in 0..<3 { average[channel] += Double(pixels[offset + channel]) }
        count += 1
      }
    }
    if count > 0 { average = average.map { $0 / count } }
    // Spatially varying edge colours at several blur scales. Moving away from an
    // edge broadens its local neighbourhood, rather than using one global gradient.
    let length = horizontal ? width : height
    let depth = horizontal ? height : width
    func edge(_ far: Bool, radius: Int) -> [[Double]] {
      var raw = [[Double]](repeating: [0, 0, 0], count: length)
      for u in 0..<length {
        for v in 0..<min(4, depth) {
          let d = far ? depth - 1 - v : v
          let offset = (horizontal ? d * width + u : u * width + d) * 4
          for c in 0..<3 { raw[u][c] += Double(pixels[offset + c]) / Double(min(4, depth)) }
        }
      }
      var sums = [[Double]](repeating: [0, 0, 0], count: length + 1)
      for u in 0..<length { for c in 0..<3 { sums[u + 1][c] = sums[u][c] + raw[u][c] } }
      return (0..<length).map { u in
        let a = max(0, u - radius)
        let b = min(length, u + radius + 1)
        return (0..<3).map { (sums[b][$0] - sums[a][$0]) / Double(b - a) }
      }
    }
    let near = [edge(false, radius: 1), edge(true, radius: 1)]
    let broad = [edge(false, radius: max(4, length / 10)), edge(true, radius: max(4, length / 10))]
    var output = [UInt8](repeating: 255, count: side * side * 4)
    for y in 0..<side {
      for x in 0..<side {
        let offset = (y * side + x) * 4
        if x >= left, x < left + width, y >= top, y < top + height {
          let sourceOffset = ((y - top) * width + x - left) * 4
          for c in 0..<3 { output[offset + c] = pixels[sourceOffset + c] }
          continue
        }
        let far = horizontal ? y >= top + height : x >= left + width
        let u = min(length - 1, max(0, horizontal ? x - left : y - top))
        let gap = horizontal ? max(top, side - top - height) : max(left, side - left - width)
        let distance =
          horizontal
          ? (far ? y - top - height + 1 : top - y) : (far ? x - left - width + 1 : left - x)
        let t = min(1, Double(distance) / Double(max(1, gap)))
        let blend = t * t * (3 - 2 * t)
        for c in 0..<3 {
          let value: Double
          switch style {
          case .white: value = 255
          case .black: value = 0
          case .sampled: value = average[c]
          case .edgeGradient:
            value = near[far ? 1 : 0][u][c] * (1 - blend) + broad[far ? 1 : 0][u][c] * blend
          case .original: value = 0
          }
          output[offset + c] = UInt8(min(255, max(0, value.rounded())))
        }
      }
    }
    guard let provider = CGDataProvider(data: Data(output) as CFData) else { return nil }
    return CGImage(
      width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
  }

  static func cropLetterbox(_ image: CGImage) -> CGImage {
    guard let bytes = rgba(image) else { return image }
    let w = image.width
    let h = image.height
    func darkLine(_ position: Int, horizontal: Bool) -> Bool {
      let count = horizontal ? w : h
      var dark = 0
      for i in 0..<count {
        let p = (horizontal ? position * w + i : i * w + position) * 4
        if max(bytes[p], bytes[p + 1], bytes[p + 2]) <= 18 { dark += 1 }
      }
      return Double(dark) / Double(count) >= 0.995
    }
    func inset(horizontal: Bool) -> Int {
      let dimension = horizontal ? h : w
      let limit = dimension / 5
      var a = 0
      var b = 0
      while a < limit, darkLine(a, horizontal: horizontal) { a += 1 }
      while b < limit, darkLine(dimension - 1 - b, horizontal: horizontal) { b += 1 }
      // Paired, narrow, uniform bars only. A dark scene is not a letterbox.
      guard a >= 2, b >= 2, a < limit, b < limit, abs(a - b) <= 2 else { return 0 }
      return min(a, b)
    }
    let y = inset(horizontal: true)
    let x = inset(horizontal: false)
    return image.cropping(to: CGRect(x: x, y: y, width: w - 2 * x, height: h - 2 * y)) ?? image
  }

  static func rgba(_ image: CGImage) -> [UInt8]? {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let success = bytes.withUnsafeMutableBytes { raw -> Bool in
      guard
        let context = CGContext(
          data: raw.baseAddress, width: image.width, height: image.height,
          bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      return true
    }
    return success ? bytes : nil
  }
}
