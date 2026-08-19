@preconcurrency import AVFoundation
import EucranteCore
import XCTest

@testable import EucranteApp

final class EucranteAppTests: XCTestCase {
  @MainActor
  func testMusicImportScriptSetsRichMetadataAndEscapesProviderText() throws {
    let metadata = MediaMetadata(
      title: "Bkab \"Speechless\"\nMix",
      artist: "Ethan Stoller",
      album: "Bkab (Speechless Mix)",
      albumArtist: "Ethan Stoller",
      composer: "Ethan Stoller",
      genre: "Electronic",
      year: 2008,
      trackNumber: 1,
      trackCount: 1,
      description: "Provider text",
      sourceID: "OANZ_nJyMtA",
      sourceURL: URL(string: "https://www.youtube.com/watch?v=OANZ_nJyMtA")
    )
    let source = MusicLibraryImporter.scriptSource(
      fileURL: URL(fileURLWithPath: "/tmp/Bkab.m4a"),
      metadata: metadata,
      artworkURL: URL(fileURLWithPath: "/tmp/cover.jpg"),
      volumeAdjustment: 29
    )

    XCTAssertTrue(source.contains(#"set artist of importedTrack to "Ethan Stoller""#))
    XCTAssertTrue(source.contains(#"set album of importedTrack to "Bkab (Speechless Mix)""#))
    XCTAssertTrue(source.contains("set year of importedTrack to 2008"))
    XCTAssertTrue(source.contains("set track number of importedTrack to 1"))
    XCTAssertTrue(source.contains("set importedTrack's volume adjustment to 29"))
    XCTAssertTrue(source.contains(#"Source ID: OANZ_nJyMtA"#))
    XCTAssertTrue(source.contains(#"Bkab \"Speechless\"\nMix"#))
    let script = try XCTUnwrap(NSAppleScript(source: source))
    var compileError: NSDictionary?
    XCTAssertTrue(script.compileAndReturnError(&compileError), "\(compileError ?? [:])")
  }

  func testYouTubeRecognitionRejectsLookalikeHosts() throws {
    XCTAssertTrue(AppModel.isYouTube(try XCTUnwrap(URL(string: "https://youtube.com/watch?v=1"))))
    XCTAssertTrue(
      AppModel.isYouTube(try XCTUnwrap(URL(string: "https://www.youtube.com/watch?v=1"))))
    XCTAssertTrue(AppModel.isYouTube(try XCTUnwrap(URL(string: "https://youtu.be/example"))))
    XCTAssertFalse(AppModel.isYouTube(try XCTUnwrap(URL(string: "https://youtube.com.evil.test"))))
    XCTAssertFalse(AppModel.isYouTube(try XCTUnwrap(URL(string: "https://notyoutube.com"))))
  }

  func testEmbeddedSignInNavigationAllowsOnlyRequiredHTTPSDomains() throws {
    let allowed = [
      "https://youtube.com/account",
      "https://accounts.google.com/signin",
      "https://www.gstatic.com/example",
      "https://lh3.googleusercontent.com/example",
      "https://youtube.googleapis.com/example",
      "about:blank",
    ]
    for value in allowed {
      XCTAssertTrue(
        YouTubeNavigationPolicy.allows(try XCTUnwrap(URL(string: value))),
        value
      )
    }

    let blocked = [
      "http://youtube.com/account",
      "https://youtube.com.evil.test/account",
      "https://google.com.evil.test/signin",
      "https://example.com/",
      "file:///tmp/example",
      "data:text/html,example",
    ]
    for value in blocked {
      XCTAssertFalse(
        YouTubeNavigationPolicy.allows(try XCTUnwrap(URL(string: value))),
        value
      )
    }
  }

  @MainActor
  func testJobStateIsPersistedBeforeMutatingCallsReturn() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("EucranteAppTests-\(UUID().uuidString)", isDirectory: true)
    let suiteName = "app.eucrante.tests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: root)
    }
    let store = JobStore(fileURL: root.appendingPathComponent("jobs.json"))
    let model = AppModel(
      defaults: defaults,
      localAcquirer: BlockingAcquirer(),
      jobStore: store
    )
    for _ in 0..<100 where !model.localToolsReady {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertTrue(model.localToolsReady)

    model.sourceText = "https://example.com/media"
    await model.submit(preset: .appleMusicEfficient)

    let job = try XCTUnwrap(model.jobs.first)
    XCTAssertEqual(try store.load().first?.id, job.id)
    model.cancel(job.id)
    XCTAssertEqual(try store.load().first?.state, .cancelled)
    model.removeFromHistory(job.id)
    XCTAssertTrue(try store.load().isEmpty)
  }

  @MainActor
  func testLocalJobCompletesThroughVerificationAndPersistsItsOutput() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("EucranteAppPipelineTests-\(UUID().uuidString)", isDirectory: true)
    let output = root.appendingPathComponent("Output", isDirectory: true)
    let suiteName = "app.eucrante.pipeline-tests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: root)
    }
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    defaults.set(
      try OutputFolderBookmark.create(for: output),
      forKey: "downloads.output-bookmark.v1"
    )
    let store = JobStore(fileURL: root.appendingPathComponent("jobs.json"))
    let model = AppModel(
      defaults: defaults,
      localAcquirer: FixtureAcquirer(),
      youtubeSessionStore: TestYouTubeSessionStore(authenticated: false),
      jobStore: store
    )
    try await waitUntil { model.localToolsReady }

    model.sourceText = "https://example.com/media"
    await model.submit(preset: .custom)
    try await waitUntil(timeout: .seconds(5)) {
      model.jobs.first?.state == .completed || model.jobs.first?.state == .failed
    }

    let job = try XCTUnwrap(model.jobs.first)
    XCTAssertEqual(job.state, .completed, job.errorMessage ?? "")
    XCTAssertEqual(job.progress, 1)
    XCTAssertEqual(job.mediaDecision, .passthrough)
    let saved = try XCTUnwrap(job.outputURL)
    XCTAssertEqual(
      saved.deletingLastPathComponent().standardizedFileURL, output.standardizedFileURL)
    XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path))
    XCTAssertGreaterThan(
      try XCTUnwrap(saved.resourceValues(forKeys: [.fileSizeKey]).fileSize), 0)
    XCTAssertEqual(try store.load().first?.state, .completed)
    XCTAssertNil(try store.load().first?.stagingPath)
  }

  @MainActor
  func testStartupMarksInterruptedJobsFailedButLeavesQueuedJobsReady() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("EucranteAppRecoveryTests-\(UUID().uuidString)", isDirectory: true)
    let suiteName = "app.eucrante.recovery-tests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: root)
    }
    let store = JobStore(fileURL: root.appendingPathComponent("jobs.json"))
    let interrupted = PersistentJob(
      sourceURL: try XCTUnwrap(URL(string: "https://example.com/interrupted")),
      preset: .appleVideoBest,
      state: .downloading
    )
    let queued = PersistentJob(
      sourceURL: try XCTUnwrap(URL(string: "https://example.com/queued")),
      preset: .appleMusicBest,
      state: .queued
    )
    try store.save([interrupted, queued])

    let model = AppModel(
      defaults: defaults,
      localAcquirer: UnavailableAcquirer(),
      youtubeSessionStore: TestYouTubeSessionStore(authenticated: false),
      jobStore: store
    )
    try await waitUntil { model.jobs.count == 2 }

    let recovered = try XCTUnwrap(model.jobs.first { $0.id == interrupted.id })
    XCTAssertEqual(recovered.state, .failed)
    XCTAssertEqual(recovered.errorCode, "interrupted")
    XCTAssertTrue(recovered.errorMessage?.contains("Retry") == true)
    XCTAssertEqual(model.jobs.first { $0.id == queued.id }?.state, .queued)
    XCTAssertEqual(try store.load().first { $0.id == interrupted.id }?.state, .failed)
  }

  @MainActor
  func testYouTubeSessionGateRetainsLinkAndSignOutCancelsActiveSave() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("EucranteAppYouTubeTests-\(UUID().uuidString)", isDirectory: true)
    let suiteName = "app.eucrante.youtube-tests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: root)
    }
    let session = TestYouTubeSessionStore(authenticated: false)
    let model = AppModel(
      defaults: defaults,
      localAcquirer: BlockingAcquirer(),
      youtubeSessionStore: session,
      jobStore: JobStore(fileURL: root.appendingPathComponent("jobs.json"))
    )
    try await waitUntil { model.localToolsReady }
    let source = "https://www.youtube.com/watch?v=fixture"
    model.sourceText = source

    await model.submit(preset: .appleVideoBest)

    XCTAssertTrue(model.showingYouTubeSignIn)
    XCTAssertEqual(model.sourceText, source)
    XCTAssertTrue(model.jobs.isEmpty)
    session.authenticated = true
    await model.refreshYouTubeSession()
    XCTAssertTrue(model.youtubeSessionReady)

    model.showingYouTubeSignIn = false
    await model.submit(preset: .appleVideoBest)
    let jobID = try XCTUnwrap(model.jobs.first?.id)
    try await waitUntil { model.jobs.first?.state == .downloading }
    await model.signOutOfYouTube()

    XCTAssertFalse(model.youtubeSessionReady)
    XCTAssertEqual(session.clearCount, 1)
    XCTAssertEqual(model.jobs.first { $0.id == jobID }?.state, .cancelled)
  }

  @MainActor
  private func waitUntil(
    timeout: Duration = .seconds(2),
    condition: @escaping @MainActor () -> Bool
  ) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
      guard clock.now < deadline else {
        XCTFail("Timed out waiting for app state.")
        return
      }
      try await Task.sleep(for: .milliseconds(10))
    }
  }
}

private actor BlockingAcquirer: LocalMediaAcquiring {
  func toolStatus() async -> LocalToolStatus {
    LocalToolStatus(
      ready: true,
      downloaderVersion: "test",
      runtimeVersion: "test",
      transcoderVersion: "test"
    )
  }

  func acquire(
    sourceURL _: URL,
    preset _: EucrantePreset,
    preferences _: DownloadPreferences,
    cookieFile _: URL?,
    workingDirectory _: URL,
    progress _: @escaping @Sendable (LocalAcquisitionProgress) -> Void
  ) async throws -> LocalAcquisitionResult {
    try await Task.sleep(for: .seconds(30))
    throw CancellationError()
  }
}

private actor FixtureAcquirer: LocalMediaAcquiring {
  func toolStatus() async -> LocalToolStatus {
    LocalToolStatus(
      ready: true,
      downloaderVersion: "fixture",
      runtimeVersion: "fixture",
      transcoderVersion: "fixture"
    )
  }

  func acquire(
    sourceURL _: URL,
    preset _: EucrantePreset,
    preferences _: DownloadPreferences,
    cookieFile _: URL?,
    workingDirectory: URL,
    progress: @escaping @Sendable (LocalAcquisitionProgress) -> Void
  ) async throws -> LocalAcquisitionResult {
    try Task.checkCancellation()
    try SecureCredentialFile.prepareDirectory(workingDirectory)
    let fixture = workingDirectory.appendingPathComponent("fixture.wav")
    try makeTestTone(at: fixture)
    let size = try fixture.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init)
    progress(LocalAcquisitionProgress(fraction: 1, bytesCompleted: size, bytesExpected: size))
    return .single(
      url: fixture,
      suggestedFilename: "Fixture.wav",
      metadata: MediaMetadata(title: "Fixture", artist: "Eucrante Tests")
    )
  }
}

private actor UnavailableAcquirer: LocalMediaAcquiring {
  func toolStatus() async -> LocalToolStatus {
    LocalToolStatus(
      ready: false,
      downloaderVersion: nil,
      runtimeVersion: nil,
      transcoderVersion: nil
    )
  }

  func acquire(
    sourceURL _: URL,
    preset _: EucrantePreset,
    preferences _: DownloadPreferences,
    cookieFile _: URL?,
    workingDirectory _: URL,
    progress _: @escaping @Sendable (LocalAcquisitionProgress) -> Void
  ) async throws -> LocalAcquisitionResult {
    throw CancellationError()
  }
}

@MainActor
private final class TestYouTubeSessionStore: YouTubeSessionStoring {
  var authenticated: Bool
  private(set) var clearCount = 0

  init(authenticated: Bool) {
    self.authenticated = authenticated
  }

  func hasAuthenticatedSession() async -> Bool { authenticated }

  func exportCookieFile(to _: URL) async throws -> URL? { nil }

  func clear() async {
    authenticated = false
    clearCount += 1
  }
}

private func makeTestTone(at url: URL) throws {
  let sampleRate = 44_100.0
  guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
    let buffer = AVAudioPCMBuffer(
      pcmFormat: format,
      frameCapacity: AVAudioFrameCount(sampleRate / 4)
    )
  else {
    throw CocoaError(.fileWriteUnknown)
  }
  buffer.frameLength = buffer.frameCapacity
  for channel in 0..<Int(format.channelCount) {
    guard let samples = buffer.floatChannelData?[channel] else { continue }
    for frame in 0..<Int(buffer.frameLength) {
      samples[frame] = Float(sin(2 * .pi * 440 * Double(frame) / sampleRate) * 0.15)
    }
  }
  let file = try AVAudioFile(forWriting: url, settings: format.settings)
  try file.write(from: buffer)
}
