import EucranteCore
@preconcurrency import WebKit
import XCTest

@testable import EucranteApp

@MainActor
final class SiteRecoveryTests: XCTestCase {
  func testStaleSessionPromptsOnlyAffectedSiteAndRechecksAfterDone() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let name = "eucrante.recovery.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer {
      defaults.removePersistentDomain(forName: name)
      try? FileManager.default.removeItem(at: root)
    }
    let inspector = RecoveryInspector()
    let session = RecoverySession()
    let model = AppModel(
      defaults: defaults, localAcquirer: RecoveryAcquirer(), localPreviewer: inspector,
      siteSessionStore: session,
      jobStore: JobStore(fileURL: root.appendingPathComponent("jobs.json")),
      previewDebounce: .zero)
    try await wait { model.localToolsReady }
    let source = URL(string: "https://www.instagram.com/reel/fixture/")!
    let site = MediaSite(source)
    model.sourceText = source.absoluteString
    try await wait { model.previewNeedsSignIn }
    XCTAssertEqual(model.siteStatuses[site], .needsSignIn)
    XCTAssertEqual(model.recoverySources[site], source)
    XCTAssertTrue(model.queue.blockedSites.contains(site))
    XCTAssertEqual(session.exported.last, source)
    XCTAssertFalse(
      model.showingSiteSignIn, "Do not launch repeated login browsers for each failure")
    model.openSiteSignIn(source)
    XCTAssertEqual(model.currentSite.name, "Instagram")
    XCTAssertTrue(model.showingSiteSignIn)
    await inspector.setFailure(nil)
    model.finishSiteSignIn()
    try await wait { model.siteStatuses[site] == .verified }
    XCTAssertNotNil(model.mediaPreview)
    XCTAssertTrue(model.recoverySources.isEmpty)
    XCTAssertTrue(model.queue.blockedSites.isEmpty)
    XCTAssertFalse(model.previewNeedsSignIn)
    let calls = await inspector.calls
    XCTAssertEqual(calls, 2)
    // One newly accessible item must not hide another item's unresolved login failure.
    let other = URL(string: "https://www.instagram.com/reel/other/")!
    await inspector.setFailure(.authenticationRequired)
    model.sourceText = source.absoluteString + "?retry=1"
    try await wait { model.previewNeedsSignIn }
    model.sourceText = other.absoluteString
    try await wait { model.previewNeedsSignIn }
    await inspector.setFailure(nil)
    model.sourceText = other.absoluteString
    try await wait { model.mediaPreview != nil }
    XCTAssertEqual(model.siteStatuses[site], .needsSignIn)
    XCTAssertFalse(model.recoverySources.isEmpty)
    model.sourceText = source.absoluteString + "?retry=1"
    try await wait { model.siteStatuses[site] == .verified }
    XCTAssertTrue(model.recoverySources.isEmpty)
    await inspector.setFailure(.networkUnavailable)
    model.sourceText = "https://www.tiktok.com/@fixture/video/2"
    try await wait { model.previewMessage != nil }
    XCTAssertFalse(model.previewNeedsSignIn)
    XCTAssertTrue(model.recoverySources.isEmpty)
  }

  func testPersistedAuthenticationFailureIsProactiveAndReconnectRetriesOnlyThoseJobs() async throws
  {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let name = "eucrante.queue-recovery.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer {
      defaults.removePersistentDomain(forName: name)
      try? FileManager.default.removeItem(at: root)
    }
    let source = URL(string: "https://instagram.com/reel/private/")!
    let site = MediaSite(source)
    let auth = PersistentJob(
      sourceURL: source, preset: .appleMusicBest, state: .failed,
      errorCode: "authenticationRequired", errorMessage: "Login required")
    let unrelated = PersistentJob(
      sourceURL: source, preset: .appleMusicBest, state: .failed,
      errorCode: "interrupted", errorMessage: "Interrupted")
    let store = JobStore(fileURL: root.appendingPathComponent("jobs.json"))
    try store.save([auth, unrelated])
    let model = AppModel(
      defaults: defaults, localAcquirer: RecoveryAcquirer(),
      siteSessionStore: RecoverySession(), jobStore: store)
    try await wait { model.localToolsReady }
    XCTAssertEqual(model.recoverySources[site], source)
    model.openSiteSignIn(source)
    model.finishSiteSignIn()
    try await wait { model.jobs.first(where: { $0.id == auth.id })?.errorCode == nil }
    XCTAssertEqual(model.jobs.first(where: { $0.id == unrelated.id })?.errorCode, "interrupted")
    XCTAssertTrue(
      model.recoverySources.isEmpty, "A new non-auth error must not leave a stale sign-in prompt")
  }

  func testCookieExportAndRemovalAreIsolatedAcrossWebsites() async throws {
    let store = WKWebsiteDataStore.nonPersistent()
    let session = SiteSessionStore(dataStore: store)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    for domain in [".youtube.com", ".instagram.com", ".youtube.com.evil.test", ".google.com"] {
      let cookie = HTTPCookie(properties: [
        .domain: domain, .path: "/", .name: "session",
        .value: "fixture", .expires: Date.now.addingTimeInterval(60),
      ])!
      await store.httpCookieStore.setCookie(cookie)
    }
    let source = URL(string: "https://www.instagram.com/reel/fixture")!
    let exported = try await session.exportCookieFile(for: source, to: root)
    let text = try String(contentsOf: XCTUnwrap(exported), encoding: .utf8)
    XCTAssertTrue(text.contains("instagram.com"))
    XCTAssertFalse(text.contains("youtube"))
    XCTAssertFalse(text.contains("google.com"))
    await session.clear(for: source)
    let instagram = await session.hasSavedCookies(for: source)
    let youtube = await session.hasSavedCookies(for: URL(string: "https://youtube.com")!)
    XCTAssertFalse(instagram)
    XCTAssertTrue(youtube)
    let youtubeExport = try await session.exportCookieFile(
      for: URL(string: "https://youtu.be/fixture")!, to: root)
    let youtubeText = try String(contentsOf: XCTUnwrap(youtubeExport), encoding: .utf8)
    XCTAssertTrue(youtubeText.contains(".youtube.com"))
    XCTAssertFalse(youtubeText.contains("evil.test"))
    XCTAssertFalse(youtubeText.contains("google.com"))
  }

  private func wait(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(4)
    while !condition() {
      if ContinuousClock.now > deadline { throw NSError(domain: "timeout", code: 1) }
      try await Task.sleep(for: .milliseconds(10))
    }
  }
}

@MainActor
private final class RecoverySession: SiteSessionStoring {
  var exported: [URL] = []
  // Stale cookies must not bypass checks.
  func hasSavedCookies(for source: URL) async -> Bool { true }
  func exportCookieFile(for source: URL, to directory: URL) async throws -> URL? {
    exported.append(source)
    return nil
  }
  func clear(for source: URL) async {}
}

private actor RecoveryInspector: LocalMediaPreviewing {
  private(set) var calls = 0
  var failure: LocalAcquisitionError? = .authenticationRequired
  func setFailure(_ error: LocalAcquisitionError?) { failure = error }
  func preview(sourceURL: URL, cookieFile: URL?, workingDirectory: URL) async throws -> MediaPreview
  {
    calls += 1
    if let failure { throw failure }
    return MediaPreview(metadata: MediaMetadata(title: "Accessible"), duration: 60, formats: [])
  }
}
private actor RecoveryAcquirer: LocalMediaAcquiring {
  func toolStatus() async -> LocalToolStatus {
    LocalToolStatus(
      ready: true, downloaderVersion: "fixture", runtimeVersion: nil, transcoderVersion: nil)
  }
  func acquire(
    sourceURL: URL, preset: EucrantePreset, preferences: DownloadPreferences,
    cookieFile: URL?, workingDirectory: URL,
    progress: @escaping @Sendable (LocalAcquisitionProgress) -> Void
  ) async throws -> LocalAcquisitionResult {
    throw LocalAcquisitionError.outputMissing
  }
}
