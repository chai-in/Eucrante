import Foundation

public actor JobStore {
  private let fileURL: URL
  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

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
    guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
    do {
      let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
      return try decoder.decode(JobLibrarySnapshot.self, from: data).jobs
    } catch {
      throw JobStoreError.read(error.localizedDescription)
    }
  }

  public func save(_ jobs: [PersistentJob]) throws {
    do {
      try fileManager.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let data = try encoder.encode(JobLibrarySnapshot(jobs: jobs))
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

  public func removeAll() throws {
    guard fileManager.fileExists(atPath: fileURL.path) else { return }
    do {
      try fileManager.removeItem(at: fileURL)
    } catch {
      throw JobStoreError.write(error.localizedDescription)
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
