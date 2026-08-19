@preconcurrency import AVFoundation
import AppKit
import EucranteCore
import SwiftUI
@preconcurrency import WebKit
import XCTest

@testable import EucranteApp

final class EucranteAppTests: XCTestCase {
  @MainActor
  func testNativeViewBodiesRenderAcrossSaveQueueSettingsAndConnectedStates() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "EucranteViewTests-\(UUID().uuidString)", isDirectory: true)
    let suiteName = "app.eucrante.view-tests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: root)
    }
    let output = root.appendingPathComponent("Track.m4a")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("audio".utf8).write(to: output)
    let jobs = [
      PersistentJob(
        sourceURL: URL(string: "https://example.com/queued")!,
        preset: .appleVideoBest,
        state: .queued,
        progress: 0.4,
        bytesCompleted: 40,
        bytesExpected: 100
      ),
      PersistentJob(
        sourceURL: URL(string: "https://example.com/completed")!,
        preset: .appleMusicBest,
        state: .completed,
        filename: "Track.m4a",
        outputPath: output.path,
        mediaDecision: .passthrough
      ),
      PersistentJob(
        sourceURL: URL(string: "https://example.com/imported")!,
        preset: .appleMusicEfficient,
        state: .completed,
        filename: "Imported.m4a",
        outputPath: output.path,
        importedToMusic: true
      ),
      PersistentJob(
        sourceURL: URL(string: "https://example.com/failed")!,
        preset: .custom,
        state: .failed,
        errorMessage: "Fixture failure"
      ),
      PersistentJob(
        sourceURL: URL(string: "https://example.com/cancelled")!,
        preset: .custom,
        state: .cancelled,
        errorMessage: "Cancelled"
      ),
    ]
    let store = JobStore(fileURL: root.appendingPathComponent("jobs.json"))
    try store.save(jobs)
    let session = TestYouTubeSessionStore(authenticated: true)
    let model = AppModel(
      defaults: defaults,
      localAcquirer: UnavailableAcquirer(),
      youtubeSessionStore: session,
      jobStore: store
    )
    try await waitUntil { model.jobs.count == jobs.count }
    await model.refreshYouTubeSession()
    model.finishYouTubeSignIn()
    try await waitUntil { model.statusMessage == "YouTube is signed in and ready." }
    model.sourceText = "https://example.com/media"
    model.musicMetadataDraft.title = "Manual title"
    model.musicMetadataDraft.year = "2026"

    render(SaveView(model: model))
    render(QueueView(model: model))
    render(SettingsView(model: model))
    render(AppShellView(model: model))
    render(YouTubeSignInView(model: model))
    for job in model.jobs {
      render(JobRow(model: model, job: job))
    }
    render(EmptyView().eucranteCard())
    _ = Color.eucranteAccent
  }

  @MainActor
  func testPrivateYouTubeCookieStoreExportsSanitizedNetscapeFileAndClears() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "EucranteCookieTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let dataStore = WKWebsiteDataStore.nonPersistent()
    let session = YouTubeSessionStore(dataStore: dataStore)
    let cookie = try XCTUnwrap(
      HTTPCookie(properties: [
        .domain: ".youtube.com",
        .path: "/watch\npath",
        .name: "SID",
        .value: "secret\tvalue",
        .secure: "TRUE",
        .expires: Date(timeIntervalSince1970: 2_000_000_000),
        HTTPCookiePropertyKey(rawValue: "HttpOnly"): "TRUE",
      ]))
    let unrelated = try XCTUnwrap(
      HTTPCookie(properties: [
        .domain: ".example.com", .path: "/", .name: "SID", .value: "other",
      ]))
    await setCookie(cookie, in: dataStore)
    await setCookie(unrelated, in: dataStore)

    let authenticated = await session.hasAuthenticatedSession()
    XCTAssertTrue(authenticated)
    let exportedValue = try await session.exportCookieFile(to: root)
    let exported = try XCTUnwrap(exportedValue)
    let text = try String(contentsOf: exported, encoding: .utf8)
    XCTAssertTrue(text.contains("youtube.com"))
    XCTAssertTrue(text.contains("SID"))
    XCTAssertTrue(text.contains("secret value"))
    XCTAssertFalse(text.contains("example.com"))
    XCTAssertFalse(text.contains("watch\npath"))
    let mode = try XCTUnwrap(
      FileManager.default.attributesOfItem(atPath: exported.path)[.posixPermissions] as? NSNumber
    ).intValue
    XCTAssertEqual(mode & 0o777, 0o600)

    await session.clear()
    let authenticatedAfterClear = await session.hasAuthenticatedSession()
    let exportAfterClear = try await session.exportCookieFile(to: root)
    XCTAssertFalse(authenticatedAfterClear)
    XCTAssertNil(exportAfterClear)
  }

  @MainActor
  func testMusicArtworkPreparationAndImportErrors() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "EucranteMusicArtworkTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("source.webp")
    let png = try XCTUnwrap(
      Data(
        base64Encoded:
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
      ))
    try png.write(to: source)

    let preparedValue = await MusicLibraryImporter.temporaryArtwork(for: source)
    let prepared = try XCTUnwrap(preparedValue)
    defer { try? FileManager.default.removeItem(at: prepared.deletingLastPathComponent()) }
    XCTAssertEqual(prepared.lastPathComponent, "cover.jpg")
    XCTAssertNotNil(NSImage(contentsOf: prepared))
    let nilArtwork = await MusicLibraryImporter.temporaryArtwork(for: nil)
    let insecureArtwork = await MusicLibraryImporter.temporaryArtwork(
      for: URL(string: "http://example.com/cover"))
    let missingArtwork = await MusicLibraryImporter.temporaryArtwork(
      for: root.appendingPathComponent("missing.png"))
    XCTAssertNil(nilArtwork)
    XCTAssertNil(insecureArtwork)
    XCTAssertNil(missingArtwork)

    do {
      try await MusicLibraryImporter().importFile(
        at: root.appendingPathComponent("missing.m4a"), metadata: nil)
      XCTFail("Expected missing file")
    } catch let error as MusicImportError {
      XCTAssertEqual(error.localizedDescription, MusicImportError.missingFile.localizedDescription)
    }
    let errors: [MusicImportError] = [
      .missingFile, .scriptUnavailable, .rejected("detail"),
    ]
    XCTAssertTrue(errors.allSatisfy { $0.errorDescription?.isEmpty == false })
  }

  func testMusicMetadataDraftValidatesNumbersAndBuildsOverrides() throws {
    var draft = MusicMetadataDraft()
    draft.title = "  Manual Title  "
    draft.artist = "Manual Artist"
    draft.year = "2026"
    draft.trackNumber = "2"

    let metadata = try XCTUnwrap(draft.metadata())
    XCTAssertEqual(metadata.title, "Manual Title")
    XCTAssertEqual(metadata.artist, "Manual Artist")
    XCTAssertEqual(metadata.year, 2026)
    XCTAssertEqual(metadata.trackNumber, 2)

    draft.discNumber = "side A"
    XCTAssertThrowsError(try draft.metadata())
  }

  func testChosenArtworkIsValidatedNormalizedAndPrivatelyPersisted() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "EucranteArtworkTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source.png")
    let png = try XCTUnwrap(
      Data(
        base64Encoded:
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
      ))
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try png.write(to: source)

    XCTAssertTrue(ArtworkStore.validateSelection(source))
    let jobID = UUID()
    let storedRoot = root.appendingPathComponent("stored", isDirectory: true)
    let saved = try ArtworkStore.persist(
      selectedURL: source,
      jobID: jobID,
      rootDirectory: storedRoot
    )

    XCTAssertEqual(saved.lastPathComponent, "cover.jpg")
    XCTAssertNotNil(NSImage(contentsOf: saved))
    let attributes = try FileManager.default.attributesOfItem(atPath: saved.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    let nonHTTPSArtwork = await ArtworkStore.cacheProviderArtwork(from: source, jobID: UUID())
    XCTAssertNil(nonHTTPSArtwork)
    XCTAssertFalse(ArtworkStore.validateSelection(root.appendingPathComponent("missing.png")))
    XCTAssertNil(ArtworkNormalizer.jpegData(from: Data()))
    XCTAssertTrue(
      ArtworkStoreError.invalidImage.errorDescription?.contains("smaller than 10 MB") == true)
    ArtworkStore.remove(jobID: jobID, rootDirectory: storedRoot)
    XCTAssertFalse(FileManager.default.fileExists(atPath: saved.path))
  }

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
      artworkURL: URL(fileURLWithPath: "/tmp/cover.jpg")
    )

    XCTAssertTrue(source.contains(#"set artist of importedTrack to "Ethan Stoller""#))
    XCTAssertTrue(source.contains(#"set album of importedTrack to "Bkab (Speechless Mix)""#))
    XCTAssertTrue(source.contains("set year of importedTrack to 2008"))
    XCTAssertTrue(source.contains("set track number of importedTrack to 1"))
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

    model.sourceText = "not a complete URL"
    await model.submit()
    XCTAssertTrue(model.errorMessage?.contains("complete HTTP or HTTPS") == true)

    model.sourceText = "https://example.com/media"
    model.musicMetadataDraft.title = "Manual Title"
    model.musicMetadataDraft.artist = "Manual Artist"
    model.musicMetadataDraft.year = "2026"
    let artwork = root.appendingPathComponent("cover.png")
    try XCTUnwrap(
      Data(
        base64Encoded:
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
      )
    ).write(to: artwork)
    model.musicMetadataDraft.artworkURL = artwork
    await model.submit(preset: .appleMusicEfficient)

    let job = try XCTUnwrap(model.jobs.first)
    XCTAssertEqual(job.metadataOverrides?.title, "Manual Title")
    XCTAssertEqual(job.metadataOverrides?.artist, "Manual Artist")
    XCTAssertEqual(job.metadataOverrides?.year, 2026)
    XCTAssertEqual(job.metadataOverrides?.artworkURL?.lastPathComponent, "cover.jpg")
    XCTAssertTrue(model.musicMetadataDraft.isEmpty)
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
  func testAppModelMergeTranscodeAndFailurePipelines() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "EucrantePipelineBranchTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let video = root.appendingPathComponent("video.mp4")
    let audio = root.appendingPathComponent("audio.wav")
    try await makeTestVideo(at: video)
    try makeTestTone(at: audio)
    let metadata = MediaMetadata(title: "Provider", artist: "Artist")
    let mergeSuite = "app.eucrante.merge.\(UUID().uuidString)"
    let transcodeSuite = "app.eucrante.transcode.\(UUID().uuidString)"
    let failureSuite = "app.eucrante.failure.\(UUID().uuidString)"
    let passthroughSuite = "app.eucrante.passthrough.\(UUID().uuidString)"
    let cancellationSuite = "app.eucrante.cancellation.\(UUID().uuidString)"
    defer {
      UserDefaults.standard.removePersistentDomain(forName: mergeSuite)
      UserDefaults.standard.removePersistentDomain(forName: transcodeSuite)
      UserDefaults.standard.removePersistentDomain(forName: failureSuite)
      UserDefaults.standard.removePersistentDomain(forName: passthroughSuite)
      UserDefaults.standard.removePersistentDomain(forName: cancellationSuite)
    }

    let mergeModel = try branchModel(
      root: root.appendingPathComponent("merge", isDirectory: true),
      acquirer: StaticResultAcquirer(
        result: .merge(
          video: video,
          audio: audio,
          suggestedFilename: "Merged.mp4",
          metadata: metadata
        )),
      suiteName: mergeSuite
    )
    try await waitUntil { mergeModel.localToolsReady }
    mergeModel.musicMetadataDraft.title = "Manual Title"
    mergeModel.sourceText = "https://example.com/merge"
    await mergeModel.submit(preset: .appleVideoBest)
    try await waitUntil(timeout: .seconds(8)) {
      mergeModel.jobs.first?.state == .completed || mergeModel.jobs.first?.state == .failed
    }
    let mergeJob = try XCTUnwrap(mergeModel.jobs.first)
    XCTAssertEqual(mergeJob.state, .completed, mergeJob.errorMessage ?? "")
    XCTAssertEqual(mergeJob.mediaMetadata?.title, "Provider")
    XCTAssertEqual(mergeJob.mediaDecision, .passthrough)
    XCTAssertEqual(mergeJob.outputURL?.pathExtension, "mp4")

    let script = root.appendingPathComponent("fake-ffmpeg")
    try Data(
      """
      #!/bin/sh
      input=''
      previous=''
      for argument do
        if [ "$previous" = '-i' ] && [ -z "$input" ]; then input="$argument"; fi
        previous="$argument"
        output="$argument"
      done
      printf 'out_time_us=500000\n'
      /bin/cp "$input" "$output"
      """.utf8
    ).write(to: script)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
    let transcodeModel = try branchModel(
      root: root.appendingPathComponent("transcode", isDirectory: true),
      acquirer: StaticResultAcquirer(
        result: .transcode(
          video: video,
          audio: audio,
          suggestedFilename: "Converted.mp4",
          duration: 1,
          quality: .best,
          metadata: metadata
        )),
      suiteName: transcodeSuite,
      videoTranscoder: AppleVideoTranscoder(executable: script)
    )
    try await waitUntil { transcodeModel.localToolsReady }
    transcodeModel.sourceText = "https://example.com/transcode"
    await transcodeModel.submit(preset: .appleVideoBest)
    try await waitUntil(timeout: .seconds(8)) {
      transcodeModel.jobs.first?.state == .completed
        || transcodeModel.jobs.first?.state == .failed
    }
    let transcodeJob = try XCTUnwrap(transcodeModel.jobs.first)
    XCTAssertEqual(transcodeJob.state, .completed, transcodeJob.errorMessage ?? "")
    XCTAssertEqual(transcodeJob.mediaDecision, .transcodeHEVC)
    XCTAssertEqual(transcodeJob.progress, 1)

    let failureModel = try branchModel(
      root: root.appendingPathComponent("failure", isDirectory: true),
      acquirer: FailingAcquirer(error: .accessDenied),
      suiteName: failureSuite
    )
    try await waitUntil { failureModel.localToolsReady }
    failureModel.sourceText = "https://example.com/failure"
    await failureModel.submit(preset: .appleMusicBest)
    try await waitUntil { failureModel.jobs.first?.state == .failed }
    XCTAssertEqual(failureModel.jobs.first?.state, .failed)
    XCTAssertTrue(failureModel.jobs.first?.errorMessage?.contains("refused") == true)

    let passthroughModel = try branchModel(
      root: root.appendingPathComponent("passthrough", isDirectory: true),
      acquirer: StaticResultAcquirer(
        result: .single(
          url: video,
          suggestedFilename: "Original.mp4",
          metadata: metadata
        )),
      suiteName: passthroughSuite
    )
    try await waitUntil { passthroughModel.localToolsReady }
    passthroughModel.sourceText = "https://example.com/passthrough"
    await passthroughModel.submit(preset: .custom)
    try await waitUntil { passthroughModel.jobs.first?.state == .completed }
    XCTAssertEqual(passthroughModel.jobs.first?.mediaDecision, .passthrough)
    XCTAssertEqual(passthroughModel.jobs.first?.outputURL, video)

    let cancellationModel = try branchModel(
      root: root.appendingPathComponent("cancellation", isDirectory: true),
      acquirer: BlockingAcquirer(),
      suiteName: cancellationSuite
    )
    try await waitUntil { cancellationModel.localToolsReady }
    cancellationModel.sourceText = "https://example.com/cancellation"
    await cancellationModel.submit(preset: .custom)
    try await waitUntil { cancellationModel.jobs.first?.state == .downloading }
    let cancellationJob = try XCTUnwrap(cancellationModel.jobs.first)
    cancellationModel.cancel(cancellationJob.id)
    try await Task.sleep(for: .milliseconds(30))
    XCTAssertEqual(cancellationModel.jobs.first?.state, .cancelled)
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
  func testAppModelValidationSettingsRetryHistoryAndIncomingLinks() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "EucranteModelBranchTests-\(UUID().uuidString)", isDirectory: true)
    let suiteName = "app.eucrante.model-branches.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: root)
    }
    let failed = PersistentJob(
      sourceURL: URL(string: "https://example.com/failed")!,
      preset: .custom,
      state: .failed,
      errorCode: "fixture",
      errorMessage: "Failed"
    )
    let completed = PersistentJob(
      sourceURL: URL(string: "https://example.com/completed")!,
      preset: .appleVideoBest,
      state: .completed
    )
    let store = JobStore(fileURL: root.appendingPathComponent("jobs.json"))
    try store.save([failed, completed])
    let model = AppModel(
      defaults: defaults,
      localAcquirer: UnavailableAcquirer(),
      youtubeSessionStore: TestYouTubeSessionStore(authenticated: false),
      jobStore: store
    )
    try await waitUntil { model.jobs.count == 2 }

    XCTAssertFalse(model.canSubmit)
    XCTAssertFalse(model.isSubmitting)
    XCTAssertEqual(model.historyJobs.count, 2)
    model.sourceText = "https://example.com/media"
    await model.submit()
    XCTAssertTrue(model.errorMessage?.contains("tools") == true)

    model.preferences.filenameStyle = .nerdy
    XCTAssertNotNil(defaults.data(forKey: "save.preferences.v1"))
    model.maximumConcurrentJobs = 99
    XCTAssertEqual(model.maximumConcurrentJobs, 4)
    XCTAssertEqual(defaults.integer(forKey: "jobs.maximum-concurrent"), 4)
    model.maximumConcurrentJobs = -2
    XCTAssertEqual(model.maximumConcurrentJobs, 1)

    model.musicMetadataDraft.title = "Temporary"
    model.clearMusicMetadata()
    XCTAssertTrue(model.musicMetadataDraft.isEmpty)
    model.openYouTubeSignIn()
    XCTAssertTrue(model.showingYouTubeSignIn)
    model.finishYouTubeSignIn()
    try await Task.sleep(for: .milliseconds(30))
    XCTAssertFalse(model.youtubeSessionReady)

    model.handleIncomingURL(
      URL(string: "eucrante://save?url=https%3A%2F%2Fexample.com%2Fshared")!)
    XCTAssertEqual(model.sourceText, "https://example.com/shared")
    XCTAssertEqual(model.statusMessage, "Ready to save the shared link.")
    model.handleIncomingURL(URL(string: "eucrante://invalid")!)
    XCTAssertTrue(model.errorMessage?.contains("valid public media URL") == true)

    model.retry(failed.id)
    XCTAssertEqual(model.jobs.first { $0.id == failed.id }?.state, .queued)
    XCTAssertNil(model.jobs.first { $0.id == failed.id }?.errorCode)
    model.cancel(UUID())
    model.removeFromHistory(UUID())
    model.clearHistory()
    XCTAssertEqual(model.jobs.map(\.id), [failed.id])
    model.resetDestinationDirectory()
    XCTAssertEqual(model.destinationDirectory.lastPathComponent, "Eucrante")
    await model.refreshLocalToolStatus()
    XCTAssertFalse(model.localToolsReady)
    XCTAssertTrue(model.localToolsMessage.contains("missing"))
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

  @MainActor
  private func render<V: View>(_ view: V) {
    let size = NSSize(width: 1_280, height: 800)
    let hostingView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
    hostingView.frame = NSRect(origin: .zero, size: size)
    hostingView.layoutSubtreeIfNeeded()
    hostingView.displayIfNeeded()
    XCTAssertEqual(hostingView.bounds.size, size)
  }

  @MainActor
  private func branchModel(
    root: URL,
    acquirer: any LocalMediaAcquiring,
    suiteName: String,
    videoTranscoder: AppleVideoTranscoder = AppleVideoTranscoder()
  ) throws -> AppModel {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let output = root.appendingPathComponent("Output", isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.set(
      try OutputFolderBookmark.create(for: output),
      forKey: "downloads.output-bookmark.v1"
    )
    return AppModel(
      defaults: defaults,
      localAcquirer: acquirer,
      videoTranscoder: videoTranscoder,
      youtubeSessionStore: TestYouTubeSessionStore(authenticated: false),
      jobStore: JobStore(fileURL: root.appendingPathComponent("jobs.json"))
    )
  }

  @MainActor
  private func setCookie(_ cookie: HTTPCookie, in dataStore: WKWebsiteDataStore) async {
    await withCheckedContinuation { continuation in
      dataStore.httpCookieStore.setCookie(cookie) { continuation.resume() }
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

private actor StaticResultAcquirer: LocalMediaAcquiring {
  let result: LocalAcquisitionResult

  init(result: LocalAcquisitionResult) {
    self.result = result
  }

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
    workingDirectory _: URL,
    progress: @escaping @Sendable (LocalAcquisitionProgress) -> Void
  ) async throws -> LocalAcquisitionResult {
    progress(LocalAcquisitionProgress(fraction: 0.5, bytesCompleted: 1, bytesExpected: 2))
    return result
  }
}

private actor FailingAcquirer: LocalMediaAcquiring {
  let error: LocalAcquisitionError

  init(error: LocalAcquisitionError) {
    self.error = error
  }

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
    workingDirectory _: URL,
    progress _: @escaping @Sendable (LocalAcquisitionProgress) -> Void
  ) async throws -> LocalAcquisitionResult {
    throw error
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

private func makeTestVideo(at url: URL) async throws {
  let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
  let input = AVAssetWriterInput(
    mediaType: .video,
    outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: 64,
      AVVideoHeightKey: 64,
    ]
  )
  let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: 64,
      kCVPixelBufferHeightKey as String: 64,
    ]
  )
  guard writer.canAdd(input) else { throw CocoaError(.fileWriteUnknown) }
  writer.add(input)
  guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
  writer.startSession(atSourceTime: .zero)
  var pixelBuffer: CVPixelBuffer?
  guard
    CVPixelBufferCreate(
      kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
      == kCVReturnSuccess,
    let buffer = pixelBuffer
  else { throw CocoaError(.fileWriteUnknown) }
  CVPixelBufferLockBaseAddress(buffer, [])
  if let base = CVPixelBufferGetBaseAddress(buffer) {
    memset(base, 0x40, CVPixelBufferGetDataSize(buffer))
  }
  CVPixelBufferUnlockBaseAddress(buffer, [])
  while !input.isReadyForMoreMediaData {
    try await Task.sleep(for: .milliseconds(5))
  }
  guard adaptor.append(buffer, withPresentationTime: .zero) else {
    throw writer.error ?? CocoaError(.fileWriteUnknown)
  }
  input.markAsFinished()
  await withCheckedContinuation { continuation in
    writer.finishWriting { continuation.resume() }
  }
  guard writer.status == .completed else {
    throw writer.error ?? CocoaError(.fileWriteUnknown)
  }
}
