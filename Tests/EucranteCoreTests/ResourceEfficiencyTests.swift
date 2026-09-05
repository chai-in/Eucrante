import Foundation
import XCTest

@testable import EucranteCore

final class ResourceEfficiencyTests: XCTestCase {
  func testIncrementalHistoryMatchesStandardEncoderAcrossEditsReorderingAndRemoval() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("jobs.json")
    let store = JobStore(fileURL: url)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    var jobs = (0..<20).map {
      PersistentJob(sourceURL: URL(string: "https://example.com/\($0)")!, preset: .custom)
    }
    for step in 0..<5 {
      switch step {
      case 1:
        jobs[3].mediaMetadata = MediaMetadata(title: "Unicode 🎵 \"title\"\nnext line")
        jobs[5].progress = 0.7
      case 2: jobs.reverse()
      case 3: jobs.removeFirst(3)
      case 4:
        jobs.insert(
          PersistentJob(sourceURL: URL(string: "https://example.com/new")!, preset: .custom), at: 0)
      default: break
      }
      try store.save(jobs)
      XCTAssertEqual(
        try Data(contentsOf: url), try encoder.encode(JobLibrarySnapshot(jobs: jobs)))
      XCTAssertEqual(try JobStore(fileURL: url).load().map(\.id), jobs.map(\.id))
    }
    let original = try Data(contentsOf: url)
    XCTAssertThrowsError(try store.save([jobs[0], jobs[0]]))
    XCTAssertEqual(try Data(contentsOf: url), original)
  }

  func testLoadedCurrentHistorySkipsStartupRewriteAndLargeHistoriesRemainWritable() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("jobs.json")
    let store = JobStore(fileURL: url)
    var job = PersistentJob(sourceURL: URL(string: "https://example.com/media")!, preset: .custom)
    try store.save([job])
    let original = try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber]
    let reopened = JobStore(fileURL: url)
    try reopened.save(reopened.load())
    XCTAssertEqual(
      try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? NSNumber,
      original as? NSNumber)
    job.mediaMetadata = MediaMetadata(description: String(repeating: "x", count: 4_200_000))
    try store.save([job])
    job.filename = "Changed"
    try store.save([job])
    XCTAssertEqual(try store.load().first?.filename, "Changed")
    try store.save([])
    XCTAssertEqual(try store.load(), [])
  }

  func testCompactHistorySkipsUnchangedWritesAndKeepsAtomicPermissions() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("jobs.json")
    let store = JobStore(fileURL: url)
    let job = PersistentJob(sourceURL: URL(string: "https://example.com/media")!, preset: .custom)
    try store.save([job])
    let first = try FileManager.default.attributesOfItem(atPath: url.path)
    let bytes = try Data(contentsOf: url)
    XCTAssertFalse(bytes.contains(0x0A))
    try store.save([job])
    let second = try FileManager.default.attributesOfItem(atPath: url.path)
    XCTAssertEqual(first[.systemFileNumber] as? NSNumber, second[.systemFileNumber] as? NSNumber)
    XCTAssertEqual(first[.modificationDate] as? Date, second[.modificationDate] as? Date)
    XCTAssertEqual(second[.posixPermissions] as? NSNumber, 0o600)
    XCTAssertEqual(try store.load().map(\.id), [job.id])
  }

  func testCachedHistoryStillRejectsExternalFutureVersionsAndBacksUpCorruption() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("jobs.json")
    let store = JobStore(fileURL: url)
    try store.save([])
    let original = try Data(contentsOf: url)
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let future = Data(
      String(decoding: original, as: UTF8.self).replacingOccurrences(
        of: "\"schemaVersion\":2", with: "\"schemaVersion\":9"
      ).utf8)
    XCTAssertEqual(future.count, original.count)
    try future.write(to: url)
    try FileManager.default.setAttributes(
      [.modificationDate: attributes[.modificationDate]!], ofItemAtPath: url.path)
    XCTAssertThrowsError(try store.save([])) {
      XCTAssertEqual($0 as? JobStoreError, .unsupportedSchema(9))
    }
    XCTAssertEqual(try Data(contentsOf: url), future)

    let corrupt = Data(repeating: 0x78, count: original.count)
    try corrupt.write(to: url)
    try store.save([])
    let files = try FileManager.default.contentsOfDirectory(
      at: root, includingPropertiesForKeys: nil)
    let backup = try XCTUnwrap(files.first { $0.lastPathComponent.contains(".corrupt-") })
    XCTAssertEqual(try Data(contentsOf: backup), corrupt)
    XCTAssertEqual(try store.load(), [])
  }
}
