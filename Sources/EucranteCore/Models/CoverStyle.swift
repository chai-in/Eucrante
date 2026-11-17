import Foundation

public enum CoverStyle: String, Codable, CaseIterable, Identifiable, Sendable {
  case original, white, black, sampled, edgeGradient
  public var id: Self { self }
  public var displayName: String {
    switch self {
    case .original: "Original"
    case .white: "White"
    case .black: "Black"
    case .sampled: "From artwork"
    case .edgeGradient: "Edge gradient"
    }
  }
}
