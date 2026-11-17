import Foundation

public struct MediaTimeRange: Codable, Equatable, Sendable {
  public let start: Double
  public let end: Double?

  public init(start: Double = 0, end: Double? = nil) throws {
    guard start.isFinite, start >= 0, end.map({ $0.isFinite && $0 > start }) ?? true else {
      throw MediaProcessingError.verification(
        "End time must be after start time; use positive, finite times.")
    }
    self.start = start
    self.end = end
  }

  public static func parse(_ text: String) throws -> Double? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty { return nil }
    let parts = text.split(separator: ":", omittingEmptySubsequences: false)
    guard (1...3).contains(parts.count) else { throw invalidTime }
    var seconds = 0.0
    for (index, part) in parts.enumerated() {
      guard let value = Double(part), value.isFinite, value >= 0,
        parts.count == 1 || index == 0 || value < 60,
        index == parts.count - 1 || value.rounded(.down) == value
      else { throw invalidTime }
      seconds = seconds * 60 + value
    }
    guard seconds.isFinite else { throw invalidTime }
    return seconds
  }

  public func duration(in sourceDuration: Double) throws -> Double {
    _ = try Self(start: start, end: end)  // Revalidate persisted and externally decoded values.
    let stop = end ?? sourceDuration
    guard sourceDuration.isFinite, start < sourceDuration, stop <= sourceDuration + 0.05 else {
      throw MediaProcessingError.verification("The selected times extend beyond this item.")
    }
    return min(stop, sourceDuration) - start
  }

  private static var invalidTime: MediaProcessingError {
    .verification("Enter times as seconds, m:ss, or h:mm:ss.")
  }
}
