import Foundation

public final class JobStore: @unchecked Sendable {
  public static let currentSchemaVersion = 1

  private let fileURL: URL
  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private let lock = NSLock()

  public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
    self.fileManager = fileManager
    self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
  }

  public func load() throws -> [PersistentJob] {
    try lock.withLock {
      guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
      do {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let snapshot = try decoder.decode(JobLibrarySnapshot.self, from: data)
        guard snapshot.schemaVersion == Self.currentSchemaVersion else {
          throw JobStoreError.read("Unsupported schema")
        }
        return snapshot.jobs
      } catch {
        throw JobStoreError.read(error.localizedDescription)
      }
    }
  }

  public func save(_ jobs: [PersistentJob]) throws {
    try lock.withLock {
      do {
        try backupUnreadableStoreIfNeeded()
        let data = try encoder.encode(
          JobLibrarySnapshot(schemaVersion: Self.currentSchemaVersion, jobs: jobs))
        _ = try SecureCredentialFile.writeAtomically(
          data,
          named: fileURL.lastPathComponent,
          to: fileURL.deletingLastPathComponent(),
          fileManager: fileManager
        )
      } catch {
        throw JobStoreError.write(error.localizedDescription)
      }
    }
  }

  public func removeAll() throws {
    try lock.withLock {
      guard fileManager.fileExists(atPath: fileURL.path) else { return }
      do {
        try fileManager.removeItem(at: fileURL)
      } catch {
        throw JobStoreError.write(error.localizedDescription)
      }
    }
  }

  public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
    let base =
      fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    return
      base
      .appendingPathComponent("Eucrante", isDirectory: true)
      .appendingPathComponent("jobs-v1.json", isDirectory: false)
  }

  private func backupUnreadableStoreIfNeeded() throws {
    guard fileManager.fileExists(atPath: fileURL.path) else { return }
    let existing = try Data(contentsOf: fileURL, options: .mappedIfSafe)
    if let snapshot = try? decoder.decode(JobLibrarySnapshot.self, from: existing),
      snapshot.schemaVersion == Self.currentSchemaVersion
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
}

public enum JobStoreError: LocalizedError, Equatable, Sendable {
  case read(String)
  case write(String)

  public var errorDescription: String? {
    switch self {
    case .read: "Eucrante could not read the saved job history."
    case .write: "Eucrante could not save the job history."
    }
  }
}
