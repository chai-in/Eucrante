import EucranteCore
@preconcurrency import Foundation
@preconcurrency import WebKit

@MainActor
protocol SiteSessionStoring: AnyObject {
  var websiteDataStore: WKWebsiteDataStore? { get }
  func hasSavedCookies(for source: URL) async -> Bool
  func exportCookieFile(for source: URL, to directory: URL) async throws -> URL?
  func clear(for source: URL) async
}

extension SiteSessionStoring {
  var websiteDataStore: WKWebsiteDataStore? { nil }
}

@MainActor
final class SiteSessionStore: SiteSessionStoring {
  private let dataStore: WKWebsiteDataStore
  var websiteDataStore: WKWebsiteDataStore? { dataStore }

  init(dataStore: WKWebsiteDataStore = .default()) {
    self.dataStore = dataStore
  }

  func hasSavedCookies(for source: URL) async -> Bool {
    await cookies().contains {
      MediaSite(source).acceptsCookie(domain: $0.domain)
        && ($0.expiresDate.map { $0 > .now } ?? true)
    }
  }

  func exportCookieFile(for source: URL, to directory: URL) async throws -> URL? {
    let eligible = await cookies().filter {
      MediaSite(source).acceptsCookie(domain: $0.domain)
        && ($0.expiresDate.map { $0 > .now } ?? true)
    }
    try Task.checkCancellation()
    guard !eligible.isEmpty else { return nil }

    var lines = [
      "# Netscape HTTP Cookie File",
      "# Generated temporarily by Eucrante from its private in-app website session.",
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

    guard let contents = String(lines.joined(separator: "\n") + "\n").data(using: .utf8) else {
      throw SiteSessionError.cookieEncoding
    }
    return try SecureCredentialFile.write(
      contents,
      named: ".eucrante-site-cookies.txt",
      to: directory
    )
  }

  func clear(for source: URL) async {
    let types = WKWebsiteDataStore.allWebsiteDataTypes()
    let site = MediaSite(source)
    let records = await dataStore.dataRecords(ofTypes: types)
    let matching = records.filter { site.includes(cookieDomain: $0.displayName) }
    await dataStore.removeData(ofTypes: types, for: matching)
    // Website records can use a registrable domain for subdomains. Delete exact-site cookies too.
    for cookie in await cookies() where site.acceptsCookie(domain: cookie.domain) {
      await dataStore.httpCookieStore.deleteCookie(cookie)
    }
  }

  private func cookies() async -> [HTTPCookie] {
    await withCheckedContinuation { continuation in
      dataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
    }
  }

  private static func field(_ value: String) -> String {
    value.replacingOccurrences(of: "\t", with: " ")
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
  }
}

private enum SiteSessionError: LocalizedError {
  case cookieEncoding

  var errorDescription: String? {
    "Eucrante could not encode its temporary website session."
  }
}
