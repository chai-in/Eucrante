import EucranteCore
import XCTest

@testable import EucranteApp

final class EucranteAppTests: XCTestCase {
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
