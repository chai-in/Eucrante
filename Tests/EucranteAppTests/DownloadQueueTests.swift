@preconcurrency import AVFoundation
import Combine
import EucranteCore
import XCTest

@testable import EucranteApp

@MainActor
final class DownloadQueueTests: XCTestCase {
  func testProgressBurstIsCoalescedAndStillCompletesDurably() async throws {
    let fixture = try QueueFixture()
    defer { fixture.remove() }
    let model = fixture.model
    try await eventually { model.localToolsReady }
    model.sourceText = "https://example.com/burst"
    await model.submit(preset: .custom)
    try await eventually { await fixture.acquirer.requests.count == 1 }
    var notifications = 0
    let subscription = model.objectWillChange.sink { notifications += 1 }
    await fixture.acquirer.sendProgressBurst()
    await fixture.acquirer.releaseNext()
    try await eventually { model.jobs.first?.state == .completed }
    XCTAssertLessThan(
      notifications, 100, "10,000 progress samples must not redraw the UI 10,000 times")
    XCTAssertEqual(model.jobs.first?.progress, 1)
    XCTAssertEqual(try fixture.store.load().first?.state, .completed)
    subscription.cancel()
  }

  func testFIFOIsStableAfterRelaunchAndRetryJoinsTheBackOfTheQueue() async throws {
    let fixture = try QueueFixture()
    defer { fixture.remove() }
    fixture.defaults.set(true, forKey: "jobs.paused")
    let request = SaveRequest(preferences: DownloadPreferences(), destination: fixture.output)
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let older = PersistentJob(
      sourceURL: URL(string: "https://example.com/older")!, preset: .custom,
      request: request, createdAt: timestamp)
    let newer = PersistentJob(
      sourceURL: URL(string: "https://example.com/newer")!, preset: .custom,
      request: request, createdAt: timestamp)
    try fixture.store.save([newer, older])
    let model = AppModel(
      defaults: fixture.defaults, localAcquirer: fixture.acquirer,
      youtubeSessionStore: QueueTestSession(), jobStore: fixture.store)
    try await eventually { model.localToolsReady }
    XCTAssertEqual(model.activeJobs.map(\.id), [older.id, newer.id])
    model.queuePaused = false
    try await eventually { await fixture.acquirer.requests.count == 1 }
    model.queuePaused = true
    model.cancel(older.id)
    await fixture.acquirer.releaseNext()
    try await eventually { model.activeJobCount == 0 }
    model.retry(older.id)
    XCTAssertEqual(model.activeJobs.map(\.id), [newer.id, older.id])
    model.queuePaused = false
    try await eventually { await fixture.acquirer.requests.count == 2 }
    await fixture.acquirer.releaseNext()
    try await eventually { await fixture.acquirer.requests.count == 3 }
    await fixture.acquirer.releaseNext()
    try await eventually { model.activeJobCount == 0 }
    let requests = await fixture.acquirer.requests
    XCTAssertEqual(requests.map { $0.source.lastPathComponent }, ["older", "newer", "older"])
  }

  func testQueueIsFIFOAndRetainsSettingsAndDestination() async throws {
    let fixture = try QueueFixture()
    defer { fixture.remove() }
    let model = fixture.model
    try await eventually { model.localToolsReady }
    model.queuePaused = true
    model.preferences.videoQuality = .p720
    model.preferences.filenameStyle = .nerdy
    for name in ["first", "second", "third"] {
      model.sourceText = "https://example.com/\(name)"
      await model.submit(preset: .custom)
    }
    XCTAssertEqual(model.activeJobCount, 0)
    XCTAssertEqual(try fixture.store.load().count, 3)
    model.preferences.videoQuality = .p2160
    model.preferences.filenameStyle = .pretty
    model.resetDestinationDirectory()
    model.queuePaused = false

    for (index, name) in ["first", "second", "third"].enumerated() {
      try await eventually { await fixture.acquirer.requests.count == index + 1 }
      let requests = await fixture.acquirer.requests
      let request = try XCTUnwrap(requests.last)
      XCTAssertEqual(request.source.lastPathComponent, name)
      XCTAssertEqual(request.preferences.videoQuality, .p720)
      XCTAssertEqual(request.preferences.filenameStyle, .nerdy)
      await fixture.acquirer.releaseNext()
    }
    try await eventually { model.activeJobCount == 0 }
    XCTAssertTrue(model.jobs.allSatisfy { $0.state == .completed })
    XCTAssertTrue(
      model.jobs.allSatisfy {
        $0.outputURL?.deletingLastPathComponent().standardizedFileURL
          == fixture.output.standardizedFileURL
      })
    XCTAssertEqual(try fixture.store.load().map(\.request), model.jobs.map(\.request))
    XCTAssertEqual(try fixture.store.load().map(\.state), model.jobs.map(\.state))
  }

  func testCancellationWaitsForWorkerAndIgnoresLateProgressBeforeRetry() async throws {
    let fixture = try QueueFixture()
    defer { fixture.remove() }
    let model = fixture.model
    try await eventually { model.localToolsReady }
    model.sourceText = "https://example.com/cancel"
    await model.submit(preset: .custom)
    try await eventually { await fixture.acquirer.requests.count == 1 }
    let id = try XCTUnwrap(model.jobs.first?.id)
    model.cancel(id)
    XCTAssertEqual(model.jobs.first?.state, .cancelling)
    model.retry(id)
    model.removeFromHistory(id)
    model.clearHistory()
    XCTAssertEqual(model.jobs.first?.state, .cancelling)
    XCTAssertEqual(model.activeJobCount, 1)
    await fixture.acquirer.releaseNext()
    try await eventually { model.activeJobCount == 0 }
    XCTAssertEqual(model.jobs.first?.state, .cancelled)
    XCTAssertNil(model.jobs.first?.outputPath)
    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.output.path).isEmpty)
    model.retry(id)
    try await eventually { await fixture.acquirer.requests.count == 2 }
    await fixture.acquirer.sendOldProgress()
    await fixture.acquirer.releaseNext()
    try await eventually { model.jobs.first?.state == .completed }
    await fixture.acquirer.sendOldProgress()
    await Task.yield()
    XCTAssertEqual(model.jobs.first?.progress, 1)
    XCTAssertEqual(model.jobs.first?.state, .completed)
    XCTAssertNil(model.jobs.first?.errorMessage)
    model.retry(id)
    XCTAssertEqual(model.jobs.first?.state, .completed)
  }

  func testConcurrencyLimitAndPauseHoldQueuedJobs() async throws {
    let fixture = try QueueFixture()
    defer { fixture.remove() }
    let model = fixture.model
    try await eventually { model.localToolsReady }
    model.maximumConcurrentJobs = 2
    for index in 0..<4 {
      model.sourceText = "https://example.com/\(index)"
      await model.submit(preset: .custom)
    }
    try await eventually { await fixture.acquirer.requests.count == 2 }
    XCTAssertEqual(model.activeJobCount, 2)
    model.queuePaused = true
    await fixture.acquirer.releaseNext()
    await fixture.acquirer.releaseNext()
    try await eventually { model.activeJobCount == 0 }
    XCTAssertEqual(model.activeJobs.count, 2)
    model.maximumConcurrentJobs = 1
    model.queuePaused = false
    try await eventually { await fixture.acquirer.requests.count == 3 }
    XCTAssertEqual(model.activeJobCount, 1)
    await fixture.acquirer.releaseNext()
    try await eventually { await fixture.acquirer.requests.count == 4 }
    await fixture.acquirer.releaseNext()
    try await eventually { model.activeJobCount == 0 }
    XCTAssertEqual(model.jobs.filter { $0.state == .completed }.count, 4)
  }

  func testEnqueueFailureRetainsInputAndDoesNotRun() async throws {
    let fixture = try QueueFixture(blockStore: true)
    defer { fixture.remove() }
    let model = fixture.model
    try await eventually { model.localToolsReady }
    model.sourceText = "https://example.com/retained"
    await model.submit()
    XCTAssertEqual(model.sourceText, "https://example.com/retained")
    XCTAssertNotNil(model.errorMessage)
    XCTAssertTrue(model.jobs.isEmpty)
    XCTAssertEqual(model.activeJobCount, 0)
  }

  func testQueueFiltersAndCustomAudioIdentity() {
    let job = PersistentJob(
      sourceURL: URL(string: "https://example.com/audio")!, preset: .custom,
      request: SaveRequest(
        preferences: DownloadPreferences(downloadMode: .audio),
        destination: URL(fileURLWithPath: "/tmp")),
      state: .failed, mediaMetadata: MediaMetadata(title: "Title"))
    XCTAssertTrue(job.isAudio)
    XCTAssertEqual(job.displayTitle, "Title")
    XCTAssertTrue(QueueFilter.all.includes(job))
    XCTAssertTrue(QueueFilter.attention.includes(job))
    XCTAssertFalse(QueueFilter.active.includes(job))
    XCTAssertFalse(QueueFilter.completed.includes(job))
  }

  private func eventually(_ condition: () async -> Bool) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(8)
    while !(await condition()) {
      guard clock.now < deadline else { throw QueueTestError.timeout }
      try await Task.sleep(for: .milliseconds(10))
    }
  }
}

private enum QueueTestError: Error { case timeout }

@MainActor
private struct QueueFixture {
  let root: URL
  let output: URL
  let suite: String
  let defaults: UserDefaults
  let store: JobStore
  let acquirer: ControlledAcquirer
  let model: AppModel

  init(blockStore: Bool = false) throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "EucranteQueue-\(UUID().uuidString)")
    output = root.appendingPathComponent("Output")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    suite = "app.eucrante.queue-test.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suite)!
    defaults.set(
      try OutputFolderBookmark.create(for: output), forKey: "downloads.output-bookmark.v1")
    let storeRoot = root.appendingPathComponent("Store")
    if blockStore { try Data("blocked".utf8).write(to: storeRoot) }
    store = JobStore(fileURL: storeRoot.appendingPathComponent("jobs.json"))
    acquirer = ControlledAcquirer()
    model = AppModel(
      defaults: defaults, localAcquirer: acquirer,
      youtubeSessionStore: QueueTestSession(), jobStore: store)
  }

  func remove() {
    defaults.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: root)
  }
}

private actor ControlledAcquirer: LocalMediaAcquiring {
  struct Request: Sendable {
    let source: URL
    let preferences: DownloadPreferences
  }
  private(set) var requests: [Request] = []
  private var continuations: [CheckedContinuation<Void, Never>] = []
  private var progressHandlers: [@Sendable (LocalAcquisitionProgress) -> Void] = []

  func toolStatus() async -> LocalToolStatus {
    LocalToolStatus(
      ready: true, downloaderVersion: "fixture", runtimeVersion: "fixture",
      transcoderVersion: "fixture")
  }

  func acquire(
    sourceURL: URL, preset: EucrantePreset, preferences: DownloadPreferences,
    cookieFile: URL?, workingDirectory: URL,
    progress: @escaping @Sendable (LocalAcquisitionProgress) -> Void
  ) async throws -> LocalAcquisitionResult {
    requests.append(Request(source: sourceURL, preferences: preferences))
    progressHandlers.append(progress)
    await withCheckedContinuation { continuations.append($0) }
    progress(LocalAcquisitionProgress(fraction: 0.7, bytesCompleted: 7, bytesExpected: 10))
    let file = workingDirectory.appendingPathComponent("fixture.wav")
    let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410)!
    buffer.frameLength = buffer.frameCapacity
    buffer.floatChannelData![0].initialize(repeating: 0, count: Int(buffer.frameLength))
    let writer = try AVAudioFile(forWriting: file, settings: format.settings)
    try writer.write(from: buffer)
    return .single(
      url: file, suggestedFilename: sourceURL.lastPathComponent + ".wav", metadata: MediaMetadata())
  }

  func releaseNext() { if !continuations.isEmpty { continuations.removeFirst().resume() } }
  func sendOldProgress() {
    progressHandlers.first?(
      LocalAcquisitionProgress(fraction: 0.2, bytesCompleted: 2, bytesExpected: 10))
  }

  func sendProgressBurst() {
    for index in 0..<10_000 {
      progressHandlers.last?(
        LocalAcquisitionProgress(
          fraction: Double(index) / 10_000, bytesCompleted: Int64(index), bytesExpected: 10_000))
    }
  }
}

@MainActor
private final class QueueTestSession: YouTubeSessionStoring {
  func hasAuthenticatedSession() async -> Bool { false }
  func exportCookieFile(to directory: URL) async throws -> URL? { nil }
  func clear() async {}
}
