import Foundation
import XCTest

@testable import EucranteCore

final class ResourceEfficiencyTests: XCTestCase {
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
        of: "\"schemaVersion\":3", with: "\"schemaVersion\":9"
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
