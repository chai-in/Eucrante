import CryptoKit
import Darwin
import Foundation

public final class JobStore: @unchecked Sendable {
  public static let currentSchemaVersion = 3
  private struct Header: Decodable { let schemaVersion: Int }

  private let fileURL: URL
  private let legacyFileURL: URL?
  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private let lock = NSLock()
  private var validatedRevision: FileRevision?
  private var writtenDigest: SHA256.Digest?

  public var directoryURL: URL { fileURL.deletingLastPathComponent() }

  public init(fileURL: URL? = nil, legacyFileURL: URL? = nil, fileManager: FileManager = .default) {
    self.fileManager = fileManager
    self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    self.legacyFileURL =
      legacyFileURL
      ?? (fileURL == nil
        ? Self.previousFileURL(for: self.fileURL, fileManager: fileManager) : nil)
    encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
  }

  public func load() throws -> [PersistentJob] {
    try lock.withLock {
      let source: URL
      if fileManager.fileExists(atPath: fileURL.path) {
        source = fileURL
      } else if let legacyFileURL, fileManager.fileExists(atPath: legacyFileURL.path) {
        source = legacyFileURL
      } else {
        return []
      }
      do {
        let data = try Data(contentsOf: source, options: .mappedIfSafe)
        let header = try decoder.decode(Header.self, from: data)
        guard (1...Self.currentSchemaVersion).contains(header.schemaVersion) else {
          throw JobStoreError.unsupportedSchema(header.schemaVersion)
        }
        let snapshot = try decoder.decode(JobLibrarySnapshot.self, from: data)
        guard Set(snapshot.jobs.map(\.id)).count == snapshot.jobs.count else {
          throw JobStoreError.read("Duplicate job identifiers")
        }
        return snapshot.jobs
      } catch let error as JobStoreError {
        throw error
      } catch {
        throw JobStoreError.read(error.localizedDescription)
      }
    }
  }

  public func save(_ jobs: [PersistentJob]) throws {
    try lock.withLock {
      do {
        let revision = FileRevision(fileURL)
        let unchangedFile = revision != nil && revision == validatedRevision
        if !unchangedFile { try backupUnreadableStoreIfNeeded() }
        let data = try encoder.encode(
          JobLibrarySnapshot(schemaVersion: Self.currentSchemaVersion, jobs: jobs))
        let digest = SHA256.hash(data: data)
        if unchangedFile, writtenDigest == digest { return }
        _ = try SecureCredentialFile.writeAtomically(
          data,
          named: fileURL.lastPathComponent,
          to: fileURL.deletingLastPathComponent(),
          fileManager: fileManager
        )
        let writtenRevision = FileRevision(fileURL)
        // A second app can replace the file immediately after our atomic rename. Cache only
        // a revision whose bytes still match this write, never a concurrent writer's schema.
        if let writtenRevision,
          let stored = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
          SHA256.hash(data: stored) == digest, FileRevision(fileURL) == writtenRevision
        {
          validatedRevision = writtenRevision
          writtenDigest = digest
        } else {
          validatedRevision = nil
          writtenDigest = nil
        }
      } catch let error as JobStoreError {
        throw error
      } catch {
        throw JobStoreError.write(error.localizedDescription)
      }
    }
  }

  public func removeAll() throws {
    // Keep an empty current snapshot so a retained v1 copy is never imported again.
    try save([])
  }

  public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
    let base =
      fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    return
      base
      .appendingPathComponent("Eucrante", isDirectory: true)
      .appendingPathComponent("jobs-v3.json", isDirectory: false)
  }

  private static func previousFileURL(for current: URL, fileManager: FileManager) -> URL {
    let directory = current.deletingLastPathComponent()
    let previous = directory.appendingPathComponent("jobs-v2.json")
    return fileManager.fileExists(atPath: previous.path)
      ? previous : directory.appendingPathComponent("jobs-v1.json")
  }

  private func backupUnreadableStoreIfNeeded() throws {
    guard fileManager.fileExists(atPath: fileURL.path) else { return }
    let existing = try Data(contentsOf: fileURL, options: .mappedIfSafe)
    if let header = try? decoder.decode(Header.self, from: existing),
      header.schemaVersion > Self.currentSchemaVersion
    {
      throw JobStoreError.unsupportedSchema(header.schemaVersion)
    }
    if let snapshot = try? decoder.decode(JobLibrarySnapshot.self, from: existing),
      (1...Self.currentSchemaVersion).contains(snapshot.schemaVersion),
      Set(snapshot.jobs.map(\.id)).count == snapshot.jobs.count
    {
      return
    }

    let pathExtension = fileURL.pathExtension.isEmpty ? "json" : fileURL.pathExtension
    let stem = fileURL.deletingPathExtension().lastPathComponent
    let backup = fileURL.deletingLastPathComponent()
      .appendingPathComponent("\(stem).corrupt-\(UUID().uuidString).\(pathExtension)")
    try fileManager.copyItem(at: fileURL, to: backup)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
  }

  // Atomic replacement changes the inode; in-place edits change ctime even if mtime is restored.
  // Revalidate external edits before overwriting so future schemas and recovery copies stay safe.
  private struct FileRevision: Equatable {
    let device: Int32
    let inode: UInt64
    let size: Int64
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
    let changedSeconds: Int
    let changedNanoseconds: Int

    init?(_ url: URL) {
      var value = stat()
      guard lstat(url.path, &value) == 0, value.st_mode & S_IFMT == S_IFREG else { return nil }
      device = value.st_dev
      inode = value.st_ino
      size = value.st_size
      modifiedSeconds = value.st_mtimespec.tv_sec
      modifiedNanoseconds = value.st_mtimespec.tv_nsec
      changedSeconds = value.st_ctimespec.tv_sec
      changedNanoseconds = value.st_ctimespec.tv_nsec
    }
  }
}

public enum JobStoreError: LocalizedError, Equatable, Sendable {
  case read(String)
  case write(String)
  case unsupportedSchema(Int)

  public var errorDescription: String? {
    switch self {
    case .read: "Eucrante could not read the saved job history."
    case .write: "Eucrante could not save the job history."
    case .unsupportedSchema:
      "This history was created by a newer Eucrante version. Update the app to open it."
    }
  }
}
