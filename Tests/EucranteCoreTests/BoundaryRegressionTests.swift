import Foundation
import XCTest

@testable import EucranteCore

final class BoundaryRegressionTests: XCTestCase {
  func testLegacyHistoryMigratesWithoutChangingTheOriginalFile() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let data = Data(#"{"schemaVersion":1,"jobs":[]}"#.utf8)
    let legacy = try SecureCredentialFile.write(data, named: "jobs-v1.json", to: root)
    let current = root.appendingPathComponent("jobs-v2.json")
    let store = JobStore(fileURL: current, legacyFileURL: legacy)
    XCTAssertEqual(try store.load(), [])
    let job = PersistentJob(sourceURL: URL(string: "https://example.com/new")!, preset: .custom)
    try store.save([job])
    XCTAssertEqual(try Data(contentsOf: legacy), data)
    XCTAssertEqual(try store.load().first?.id, job.id)
    let snapshot =
      try JSONSerialization.jsonObject(with: Data(contentsOf: current)) as? [String: Any]
    XCTAssertEqual(snapshot?["schemaVersion"] as? Int, 2)
    try store.removeAll()
    XCTAssertTrue(try store.load().isEmpty)
    XCTAssertEqual(try Data(contentsOf: legacy), data)
  }

  func testFutureHistoryCannotBeReplaced() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let data = Data(#"{"schemaVersion":99,"jobs":[{"state":"future"}]}"#.utf8)
    let url = try SecureCredentialFile.write(data, named: "jobs.json", to: root)
    let store = JobStore(fileURL: url)
    XCTAssertThrowsError(try store.load()) {
      XCTAssertEqual($0 as? JobStoreError, .unsupportedSchema(99))
    }
    XCTAssertThrowsError(try store.save([])) {
      XCTAssertEqual($0 as? JobStoreError, .unsupportedSchema(99))
    }
    XCTAssertEqual(try Data(contentsOf: url), data)
  }

  func testWorkspaceRecoveryRemovesHiddenPreviewCookiesAndDoesNotFollowLinks() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = DownloadWorkspace(root: root.appendingPathComponent("App"))
    let external = root.appendingPathComponent("External")
    let cookieName = ".eucrante-youtube-cookies.txt"
    let externalCookie = try SecureCredentialFile.write(
      Data("external".utf8), named: cookieName, to: external)
    let staging = workspace.staging(for: UUID())
    _ = try SecureCredentialFile.write(Data("job".utf8), named: cookieName, to: staging)
    let preview = workspace.jobs.appendingPathComponent(".preview-\(UUID().uuidString)")
    _ = try SecureCredentialFile.write(Data("preview".utf8), named: cookieName, to: preview)
    let link = workspace.staging(for: UUID())
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
    try workspace.recoverTransientFiles()
    XCTAssertFalse(FileManager.default.fileExists(atPath: preview.path))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: staging.appendingPathComponent(cookieName).path))
    XCTAssertEqual(try String(contentsOf: externalCookie, encoding: .utf8), "external")
  }

  func testProviderNumericExtremesDoNotOverflowPreview() throws {
    let video = MediaPreviewFormat(
      identifier: "video", container: "mp4", videoCodec: "vp9", audioCodec: nil,
      width: 3840, height: 2160, frameRate: .greatestFiniteMagnitude,
      totalBitrate: .greatestFiniteMagnitude,
      audioBitrate: nil, fileSize: .max, approximateFileSize: nil)
    let audio = MediaPreviewFormat(
      identifier: "audio", container: "m4a", videoCodec: nil, audioCodec: "mp4a",
      width: nil, height: nil, frameRate: nil, totalBitrate: .infinity,
      audioBitrate: .greatestFiniteMagnitude, fileSize: .max, approximateFileSize: nil)
    let preview = MediaPreview(
      metadata: MediaMetadata(), duration: .greatestFiniteMagnitude, formats: [video, audio])
    XCTAssertNil(preview.output(for: .appleVideoBest)?.estimatedByteCount)
    XCTAssertNil(preview.output(for: .appleMusicBest)?.quality)
    let estimated = MediaPreviewFormat(
      identifier: "estimated", container: "m4a", videoCodec: nil, audioCodec: "mp4a",
      width: nil, height: nil, frameRate: nil, totalBitrate: .greatestFiniteMagnitude,
      audioBitrate: nil, fileSize: nil, approximateFileSize: nil)
    XCTAssertNil(
      MediaPreview(
        metadata: MediaMetadata(), duration: .greatestFiniteMagnitude, formats: [estimated]
      )
      .output(for: .appleMusicBest)?.estimatedByteCount)
  }

  func testCancelledProcessCannotLaunch() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    let cancellable = CancellableProcess(process)
    cancellable.cancel()
    XCTAssertThrowsError(try cancellable.start()) { XCTAssertTrue($0 is CancellationError) }
    XCTAssertFalse(process.isRunning)
  }

  func testOversizedHelperLineFailsWithBoundedError() async throws {
    let runner = LocalProcessRunner()
    do {
      _ = try await runner.run(
        executable: URL(fileURLWithPath: "/usr/bin/awk"),
        arguments: ["BEGIN { printf \"%05000000d\\n\", 1 }"], onLine: { _ in })
      XCTFail("Expected oversized output to be rejected")
    } catch {
      XCTAssertEqual(error as? LocalAcquisitionError, .outputTooLarge)
    }
  }

  func testInvalidCustomMediaLeavesNoPublishedOrTemporaryFiles() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let input = try SecureCredentialFile.write(Data("not media".utf8), named: "input.mp4", to: root)
    let destination = root.appendingPathComponent("Output")
    let sentinel = try SecureCredentialFile.write(
      Data("existing".utf8), named: "Movie.mp4", to: destination)
    do {
      _ = try await LocalMediaProcessor().process(
        input, preset: .custom, suggestedFilename: "Movie.mp4", destination: destination)
      XCTFail("Expected invalid media to fail")
    } catch {
      XCTAssertEqual(
        try FileManager.default.contentsOfDirectory(atPath: destination.path), ["Movie.mp4"])
      XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "existing")
    }
  }
}
