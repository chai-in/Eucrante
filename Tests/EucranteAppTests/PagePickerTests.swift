import EucranteCore
import XCTest

@testable import EucranteApp

@MainActor
final class PagePickerTests: XCTestCase {
  func testVerificationKeepsPageOrderBoundsConcurrencyAndCleansStaging() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let inspector = PageInspector()
    let model = PagePickerModel(
      previewer: inspector, session: PageSession(), workspace: DownloadWorkspace(root: root))
    model.load(try selection(["one", "bad", "three", "four"]))
    try await waitFor { !model.running }
    XCTAssertEqual(
      model.rows.map { $0.item.url.lastPathComponent }, ["one", "bad", "three", "four"])
    XCTAssertEqual(model.rows.compactMap(\.preview).count, 3)
    XCTAssertNotNil(model.rows[1].error)
    let maximum = await inspector.maximum
    XCTAssertLessThanOrEqual(maximum, PagePickerModel.workerLimit)
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Jobs").path),
      [])
  }

  func testReplacementAndStopWaitForSupersededInspection() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let inspector = PageInspector()
    let model = PagePickerModel(
      previewer: inspector, session: PageSession(), workspace: DownloadWorkspace(root: root))
    model.load(try selection(["old", "older", "unstarted"]))
    await Task.yield()
    model.load(try selection(["new"]))
    try await waitFor { !model.running }
    XCTAssertEqual(model.rows.map { $0.item.url.lastPathComponent }, ["new"])
    XCTAssertEqual(model.rows.first?.preview?.metadata.title, "new")
    model.load(try selection(["cancel", "cancel2"]))
    await model.stop()
    XCTAssertFalse(model.running)
    let active = await inspector.active
    let maximum = await inspector.maximum
    XCTAssertEqual(active, 0)
    XCTAssertLessThanOrEqual(maximum, PagePickerModel.workerLimit)
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Jobs").path),
      [])
  }

  func testRepeatUsesVerifiedCacheAndSessionChangeForcesFreshChecks() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let inspector = PageInspector()
    let model = PagePickerModel(
      previewer: inspector, session: PageSession(), workspace: DownloadWorkspace(root: root))
    let page = try selection(["one", "bad", "three"])
    model.load(page)
    try await waitFor { !model.running }
    let initial = await inspector.calls
    model.load(page)
    XCTAssertFalse(model.running)
    XCTAssertNotNil(model.rows[1].error)
    let repeated = await inspector.calls
    XCTAssertEqual(initial, repeated)
    model.retryFailures()
    try await waitFor { !model.running }
    let retried = await inspector.calls
    XCTAssertEqual(retried, initial + 1)
    await model.invalidateSession(for: MediaSite(URL(string: "https://example.com")!))
    model.load(page)
    try await waitFor { !model.running }
    let refreshed = await inspector.calls
    XCTAssertEqual(refreshed, retried + 3)
    await model.stop()
  }

  private func selection(_ paths: [String]) throws -> PageMediaSelection {
    let object: [String: Any] = [
      "page": "https://example.com", "title": "Page", "truncated": false,
      "items": paths.map { ["url": "https://example.com/\($0)", "title": $0] },
    ]
    var components = URLComponents(string: "eucrante://page")!
    components.queryItems = [
      URLQueryItem(
        name: "payload",
        value: String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self))
    ]
    return try PageMediaSelection.decode(components.url!)
  }

  private func waitFor(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(4)
    while !condition() {
      guard ContinuousClock.now < deadline else { throw NSError(domain: "timeout", code: 1) }
      try await Task.sleep(for: .milliseconds(10))
    }
  }
}

private actor PageInspector: LocalMediaPreviewing {
  private(set) var calls = 0
  private(set) var active = 0
  private(set) var maximum = 0
  func preview(sourceURL: URL, cookieFile: URL?, workingDirectory: URL) async throws -> MediaPreview
  {
    calls += 1
    active += 1
    maximum = max(maximum, active)
    defer { active -= 1 }
    try await Task.sleep(for: .milliseconds(60))
    if sourceURL.lastPathComponent == "bad" { throw LocalAcquisitionError.formatUnavailable }
    return MediaPreview(
      metadata: MediaMetadata(title: sourceURL.lastPathComponent), duration: 60,
      formats: [
        MediaPreviewFormat(
          identifier: "140", container: "m4a", videoCodec: nil, audioCodec: "mp4a",
          width: nil, height: nil, frameRate: nil, totalBitrate: 128, audioBitrate: 128,
          fileSize: 960000, approximateFileSize: nil)
      ])
  }
}

@MainActor
private final class PageSession: SiteSessionStoring {
  func hasSavedCookies(for source: URL) async -> Bool { false }
  func exportCookieFile(for source: URL, to directory: URL) async throws -> URL? { nil }
  func clear(for source: URL) async {}
}
