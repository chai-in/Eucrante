@preconcurrency import Foundation
@preconcurrency import WebKit

@MainActor
final class YouTubeSessionStore {
  private let dataStore = WKWebsiteDataStore.default()

  func hasAuthenticatedSession() async -> Bool {
    let authenticatedNames: Set<String> = [
      "LOGIN_INFO", "SAPISID", "APISID", "SID", "HSID", "SSID", "__Secure-1PAPISID",
      "__Secure-3PAPISID", "__Secure-1PSID", "__Secure-3PSID",
    ]
    return await cookies().contains { cookie in
      Self.isYouTube(cookie.domain) && authenticatedNames.contains(cookie.name)
    }
  }

  func exportCookieFile(to directory: URL) async throws -> URL? {
    let eligible = await cookies().filter { Self.isYouTube($0.domain) }
    guard !eligible.isEmpty else { return nil }

    var lines = [
      "# Netscape HTTP Cookie File",
      "# Generated temporarily by Eucrante from its private in-app YouTube session.",
      "# This file is deleted immediately after media acquisition.",
      "",
    ]
    for cookie in eligible {
      let domain = Self.field(cookie.domain)
      let cookieDomain = cookie.isHTTPOnly ? "#HttpOnly_\(domain)" : domain
      let includeSubdomains = domain.hasPrefix(".") ? "TRUE" : "FALSE"
      let secure = cookie.isSecure ? "TRUE" : "FALSE"
      let expires = cookie.expiresDate.map { Int($0.timeIntervalSince1970) } ?? 0
      lines.append(
        [
          cookieDomain,
          includeSubdomains,
          Self.field(cookie.path),
          secure,
          String(expires),
          Self.field(cookie.name),
          Self.field(cookie.value),
        ].joined(separator: "\t"))
    }

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(".eucrante-youtube-cookies.txt")
    try (lines.joined(separator: "\n") + "\n").write(
      to: url,
      atomically: true,
      encoding: .utf8
    )
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    return url
  }

  func clear() async {
    let types = WKWebsiteDataStore.allWebsiteDataTypes()
    await withCheckedContinuation { continuation in
      dataStore.removeData(ofTypes: types, modifiedSince: .distantPast) {
        continuation.resume()
      }
    }
  }

  private func cookies() async -> [HTTPCookie] {
    await withCheckedContinuation { continuation in
      dataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
    }
  }

  private static func isYouTube(_ domain: String) -> Bool {
    let normalized = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    return normalized == "youtube.com" || normalized.hasSuffix(".youtube.com")
  }

  private static func field(_ value: String) -> String {
    value.replacingOccurrences(of: "\t", with: " ")
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
  }
}
