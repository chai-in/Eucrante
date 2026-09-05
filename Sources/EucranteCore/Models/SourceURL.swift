import Foundation

public enum SourceURLValidator {
  public static func isYouTube(_ url: URL) -> Bool {
    guard let host = url.host?.lowercased() else { return false }
    return host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be"
  }

  public static func validate(_ input: String) throws -> URL {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw SourceURLValidationError.empty }
    guard trimmed.utf8.count <= 8_192 else { throw SourceURLValidationError.tooLong }
    guard let components = URLComponents(string: trimmed),
      let scheme = components.scheme?.lowercased(),
      ["http", "https"].contains(scheme),
      components.user == nil,
      components.password == nil,
      let host = components.host,
      !host.isEmpty,
      let url = components.url
    else {
      throw SourceURLValidationError.invalid
    }
    return url
  }
}

public enum SourceURLValidationError: LocalizedError, Equatable, Sendable {
  case empty
  case invalid
  case tooLong

  public var errorDescription: String? {
    switch self {
    case .empty: "Paste a public media link first."
    case .invalid: "Enter a complete HTTP or HTTPS link."
    case .tooLong: "This link is too long to process safely."
    }
  }
}
