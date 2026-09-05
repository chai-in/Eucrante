import AppKit
import EucranteCore
import SwiftUI
import XCTest

@testable import EucranteApp

@MainActor
final class PreviewLifecycleTests: XCTestCase {
  func testCompactAndWideNativeLayoutsRender() async throws {
    let model = try PreviewFixture.makeModel()
    defer {
      try? FileManager.default.removeItem(
        at: model.destinationDirectory.deletingLastPathComponent())
    }
    try await waitFor { model.localToolsReady && model.mediaPreview != nil }
    for size in [NSSize(width: 720, height: 520), NSSize(width: 1280, height: 800)] {
      try snapshot(AppShellView(model: model), size: size, name: "save-\(Int(size.width))")
      try snapshot(
        QueueView(model: model), size: NSSize(width: size.width - 175, height: size.height - 52),
        name: "queue-\(Int(size.width))")
    }
    try snapshot(
      SettingsView(model: model), size: NSSize(width: 600, height: 500), name: "settings")
  }

  private func snapshot<V: View>(_ view: V, size: NSSize, name: String) throws {
    let host = NSHostingView(
      rootView: view.frame(width: size.width, height: size.height)
        .background(Color(nsColor: .windowBackgroundColor)))
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.contentView = host
    host.frame = NSRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    XCTAssertGreaterThan(bitmap.pixelsWide, 0)
    XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
    if let directory = ProcessInfo.processInfo.environment["EUCRANTE_UI_SNAPSHOT_DIRECTORY"] {
      let root = URL(fileURLWithPath: directory, isDirectory: true)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        .write(to: root.appendingPathComponent(name + ".png"))
    }
  }

  func testStoppingPreviewWaitsForAllSupersededCookieExportsAndPurgesFiles() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let session = SuspendedExportSession()
    let previewer = CountingPreviewer()
    let preview = LinkPreviewModel(
      previewer: previewer, session: session,
      workspace: DownloadWorkspace(root: root), debounce: .zero)
    preview.schedule("https://youtube.com/watch?v=first", toolsReady: true, youtubeReady: true)
    try await waitFor { session.pending.count == 1 }
    preview.schedule("https://youtube.com/watch?v=second", toolsReady: true, youtubeReady: true)
    try await waitFor { session.pending.count == 2 }
    var stopped = false
    let stopping = Task {
      await preview.stop()
      stopped = true
    }
    await Task.yield()
    XCTAssertFalse(stopped)
    session.releaseAll()
    await stopping.value
    XCTAssertTrue(stopped)
    XCTAssertNil(preview.media)
    XCTAssertFalse(preview.isLoading)
    let requests = await previewer.count
    XCTAssertEqual(requests, 0)
    let directories = try FileManager.default.contentsOfDirectory(
      atPath: root.appendingPathComponent("Jobs").path)
    XCTAssertTrue(directories.isEmpty)
  }

  func testDebugFixtureCompletesWithoutOpeningTheNormalLibrary() async throws {
    let model = try PreviewFixture.makeModel()
    try await waitFor { model.localToolsReady && model.mediaPreview != nil }
    XCTAssertTrue(model.destinationDirectory.path.contains("Eucrante-Preview-"))
    XCTAssertEqual(model.jobs.count, 2)
    XCTAssertEqual(model.mediaPreview?.metadata.title, "Studio Sample")
    await model.submit(preset: .appleMusicBest)
    try await waitFor(timeout: .seconds(10)) { model.activeJobCount == 0 }
    XCTAssertEqual(model.jobs.first?.state, .completed, model.jobs.first?.errorMessage ?? "")
    let directory = model.destinationDirectory.deletingLastPathComponent()
    try FileManager.default.removeItem(at: directory)
  }

  func testIdenticalPreviewRequestsReuseCurrentResultUntilInvalidated() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let previewer = CountingPreviewer()
    let preview = LinkPreviewModel(
      previewer: previewer, session: SuspendedExportSession(),
      workspace: DownloadWorkspace(root: root), debounce: .milliseconds(10))
    for _ in 0..<30 {
      preview.schedule(" https://example.com/media ", toolsReady: true, youtubeReady: false)
    }
    try await waitFor { preview.media != nil }
    for _ in 0..<30 {
      preview.schedule("https://example.com/media", toolsReady: true, youtubeReady: true)
    }
    let count = await previewer.count
    XCTAssertEqual(count, 1)
    await preview.stop()
    preview.schedule("https://example.com/media", toolsReady: true, youtubeReady: false)
    try await waitFor { preview.media != nil }
    let refreshed = await previewer.count
    XCTAssertEqual(refreshed, 2)
  }

  private func waitFor(timeout: Duration = .seconds(3), _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
      guard ContinuousClock.now < deadline else { throw PreviewTestError.timeout }
      try await Task.sleep(for: .milliseconds(10))
    }
  }
}

private enum PreviewTestError: Error { case timeout }

@MainActor
private final class SuspendedExportSession: YouTubeSessionStoring {
  var pending: [CheckedContinuation<Void, Never>] = []
  func hasAuthenticatedSession() async -> Bool { true }
  func exportCookieFile(to directory: URL) async throws -> URL? {
    await withCheckedContinuation { pending.append($0) }
    return try SecureCredentialFile.write(
      Data("test cookie".utf8), named: ".eucrante-youtube-cookies.txt", to: directory)
  }
  func clear() async {}
  func releaseAll() {
    let saved = pending
    pending = []
    for continuation in saved { continuation.resume() }
  }
}

private actor CountingPreviewer: LocalMediaPreviewing {
  private(set) var count = 0
  func preview(sourceURL: URL, cookieFile: URL?, workingDirectory: URL) async throws -> MediaPreview
  {
    count += 1
    return MediaPreview(metadata: MediaMetadata(), duration: nil, formats: [])
  }
}
