import Foundation

/// A website boundary, not an assumption that every cookie proves a working login.
public struct MediaSite: Hashable, Sendable, Identifiable {
  public let host: String
  public var id: String { host }
  public init(_ source: URL) {
    let hostname = source.host?.lowercased() ?? ""
    if SourceURLValidator.isYouTube(source) {
      host = "youtube.com"
    } else if let provider = [
      "instagram.com", "tiktok.com", "vimeo.com", "soundcloud.com", "dailymotion.com",
      "twitter.com", "x.com",
    ].first(where: { hostname == $0 || hostname.hasSuffix(".\($0)") }) {
      host = provider
    } else {
      host = hostname.hasPrefix("www.") ? String(hostname.dropFirst(4)) : hostname
    }
  }
  public var name: String {
    switch host {
    case "youtube.com": "YouTube"
    case "instagram.com": "Instagram"
    case "tiktok.com": "TikTok"
    default: host
    }
  }
  public var home: URL { URL(string: "https://\(host)/")! }
  public var signInURL: URL {
    if host == "youtube.com" {
      return URL(
        string:
          "https://accounts.google.com/AccountChooser?service=youtube&continue=https%3A%2F%2Fwww.youtube.com%2Faccount"
      )!
    }
    return home
  }
  public func acceptsCookie(domain: String) -> Bool {
    let normalized = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    // WebKit enforces public-suffix rules when accepting cookies. Include applicable
    // parent-domain cookies for arbitrary subdomain sites, just as the browser would.
    return includes(cookieDomain: domain)
      || (domain.hasPrefix(".") && host.hasSuffix(".\(normalized)"))
  }
  public func includes(cookieDomain: String) -> Bool {
    let domain = cookieDomain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    // Export this site's cookies only. Never export identity-provider or unrelated sessions.
    return domain == host || domain.hasSuffix(".\(host)")
  }
}
