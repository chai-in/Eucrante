import Foundation

public enum EndpointSecurityPolicy {
  public static func validate(_ input: String) throws -> URL {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw EndpointSecurityError.empty }
    guard trimmed.utf8.count <= 2_048 else { throw EndpointSecurityError.tooLong }
    guard let components = URLComponents(string: trimmed),
      let scheme = components.scheme?.lowercased(),
      ["http", "https"].contains(scheme),
      let host = components.host,
      !host.isEmpty,
      components.user == nil,
      components.password == nil,
      components.query == nil,
      components.fragment == nil,
      let url = components.url
    else {
      throw EndpointSecurityError.invalid
    }

    guard scheme == "https" || isPrivateDevelopmentHost(host) else {
      throw EndpointSecurityError.publicHTTP
    }
    return url
  }

  public static func allowsCredentials(to endpoint: URL) -> Bool {
    switch endpoint.scheme?.lowercased() {
    case "https":
      true
    case "http":
      endpoint.host.map(isLoopbackHost) ?? false
    default:
      false
    }
  }

  public static func allowsConnection(to endpoint: URL) -> Bool {
    guard let components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
      let scheme = components.scheme?.lowercased(),
      let host = components.host,
      components.user == nil,
      components.password == nil,
      components.query == nil,
      components.fragment == nil
    else { return false }

    return scheme == "https" || (scheme == "http" && isPrivateDevelopmentHost(host))
  }

  private static func isPrivateDevelopmentHost(_ host: String) -> Bool {
    let normalized = normalizedHost(host)
    if isLoopbackHost(normalized) || normalized.hasSuffix(".local") || !normalized.contains(".") {
      return true
    }

    if let octets = ipv4Octets(normalized) {
      return octets[0] == 10
        || (octets[0] == 172 && (16...31).contains(octets[1]))
        || (octets[0] == 192 && octets[1] == 168)
        || (octets[0] == 169 && octets[1] == 254)
    }

    guard normalized.contains(":") else { return false }
    return normalized.hasPrefix("fc") || normalized.hasPrefix("fd")
      || ["fe8", "fe9", "fea", "feb"].contains(where: normalized.hasPrefix)
  }

  private static func isLoopbackHost(_ host: String) -> Bool {
    let normalized = normalizedHost(host)
    if normalized == "localhost" || normalized.hasSuffix(".localhost") || normalized == "::1" {
      return true
    }
    return ipv4Octets(normalized)?.first == 127
  }

  private static func normalizedHost(_ host: String) -> String {
    host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
  }

  private static func ipv4Octets(_ host: String) -> [UInt8]? {
    let parts = host.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4 else { return nil }
    let octets = parts.compactMap { UInt8($0) }
    return octets.count == 4 ? octets : nil
  }
}

public enum EndpointSecurityError: LocalizedError, Equatable, Sendable {
  case empty
  case invalid
  case tooLong
  case publicHTTP

  public var errorDescription: String? {
    switch self {
    case .empty:
      "Enter your processing endpoint."
    case .invalid:
      "Enter an HTTP or HTTPS endpoint without credentials, a query, or a fragment."
    case .tooLong:
      "The processing endpoint is too long."
    case .publicHTTP:
      "Public processing endpoints must use HTTPS."
    }
  }
}
