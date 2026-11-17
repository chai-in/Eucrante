import XCTest

@testable import EucranteCore

final class SiteDiagnosticsTests: XCTestCase {
  func testFailuresDoNotMistakeEvery403OrNetworkErrorForLogin() {
    let cases: [(String, LocalAcquisitionError)] = [
      ("Instagram: login required", .authenticationRequired),
      ("Cookies are no longer valid", .authenticationRequired),
      ("Please log in to access this content", .authenticationRequired),
      ("Unsupported URL: https://example.com", .unsupportedSite),
      ("DRM protected", .protectedMedia),
      ("Unable to download webpage: HTTP Error 403: Forbidden", .accessDenied),
      ("HTTP Error 429: Too Many Requests", .rateLimited),
      ("Connection timed out", .networkUnavailable),
      ("Requested format is not available", .formatUnavailable),
      ("Unexpected extractor failure", .processFailed(1)),
    ]
    for (message, expected) in cases {
      XCTAssertEqual(LocalMediaAcquirer.processError(status: 1, diagnostic: message), expected)
      XCTAssertFalse(expected.localizedDescription.contains("YouTube"))
    }
  }
  func testMuxedAudioPreviewDoesNotClaimVideoBytesAsAudioSize() throws {
    let format = MediaPreviewFormat(
      identifier: "combined", container: "mp4", videoCodec: "avc1",
      audioCodec: "mp4a.40.2", width: 1920, height: 1080, frameRate: 30,
      totalBitrate: 4000, audioBitrate: 128, fileSize: 30_000_000, approximateFileSize: nil)
    let preview = MediaPreview(metadata: MediaMetadata(), duration: 60, formats: [format])
    let audio = try XCTUnwrap(preview.output(for: .appleMusicBest))
    XCTAssertEqual(audio.estimatedByteCount, 960_000)
    XCTAssertTrue(audio.sizeIsEstimate)
    XCTAssertEqual(audio.codec, "AAC")
  }
  func testStartupPurgesBothOldAndWebsiteCookieExports() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = DownloadWorkspace(root: root)
    let staging = workspace.staging(for: UUID())
    for name in [".eucrante-youtube-cookies.txt", ".eucrante-site-cookies.txt"] {
      _ = try SecureCredentialFile.write(Data("fixture".utf8), named: name, to: staging)
    }
    try workspace.recoverTransientFiles()
    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty)
  }
  func testSiteBoundariesRejectLookalikesAndHandleProviderAliases() {
    let youtube = MediaSite(URL(string: "https://youtu.be/fixture")!)
    XCTAssertEqual(youtube.host, "youtube.com")
    XCTAssertTrue(youtube.includes(cookieDomain: ".youtube.com"))
    XCTAssertFalse(youtube.includes(cookieDomain: "youtube.com.evil.test"))
    XCTAssertFalse(youtube.includes(cookieDomain: ".google.com"))
    XCTAssertEqual(MediaSite(URL(string: "https://m.tiktok.com/video/1")!).host, "tiktok.com")
    XCTAssertEqual(
      MediaSite(URL(string: "https://www.custom.example.com/watch/1")!).host, "custom.example.com")
  }
}
