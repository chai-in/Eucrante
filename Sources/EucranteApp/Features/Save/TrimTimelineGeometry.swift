import EucranteCore
import Foundation

struct TrimTimelineGeometry: Equatable {
  let duration: Double
  var zoom: Double = 1
  var origin: Double = 0

  var span: Double { duration / max(1, zoom) }
  var upper: Double { min(duration, origin + span) }
  var maximumZoom: Double { max(1, min(200, duration / 2)) }

  mutating func setZoom(_ value: Double, around time: Double) {
    zoom = min(maximumZoom, max(1, value))
    origin = min(max(0, time - span / 2), max(0, duration - span))
  }

  func time(at fraction: Double) -> Double {
    min(duration, max(0, origin + min(1, max(0, fraction)) * span))
  }

  func fraction(at time: Double) -> Double { (time - origin) / span }

  static func bounds(start: String, end: String, duration: Double) -> (Double, Double)? {
    do {
      let range = try MediaTimeRange(
        start: MediaTimeRange.parse(start) ?? 0,
        end: MediaTimeRange.parse(end))
      _ = try range.duration(in: duration)
      return (range.start, min(duration, range.end ?? duration))
    } catch { return nil }
  }

  static func timestamp(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0, seconds < 10_000_000 else { return "0:00.000" }
    let ms = Int((seconds * 1000).rounded())
    if ms >= 3_600_000 {
      return String(
        format: "%d:%02d:%02d.%03d", ms / 3_600_000, ms / 60_000 % 60,
        ms / 1000 % 60, ms % 1000)
    }
    return String(format: "%d:%02d.%03d", ms / 60_000, ms / 1000 % 60, ms % 1000)
  }
}
