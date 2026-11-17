import Foundation

public struct DownloadWorkspace: Sendable {
  public let root: URL

  public init(root: URL) {
    self.root = root
  }

  public var jobs: URL { root.appendingPathComponent("Jobs", isDirectory: true) }
  public var artwork: URL { root.appendingPathComponent("Artwork", isDirectory: true) }

  public func staging(for id: UUID) -> URL {
    jobs.appendingPathComponent(id.uuidString, isDirectory: true)
  }

  public func removeStaging(for id: UUID) {
    try? FileManager.default.removeItem(at: staging(for: id))
  }

  public func recoverTransientFiles() throws {
    try SecureCredentialFile.prepareDirectory(jobs)
    let directories = try FileManager.default.contentsOfDirectory(
      at: jobs, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    for directory in directories {
      let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
      if directory.lastPathComponent.hasPrefix(".preview-")
        || directory.lastPathComponent.hasPrefix(".page-")
      {
        try FileManager.default.removeItem(at: directory)
      } else if UUID(uuidString: directory.lastPathComponent) != nil {
        try SecureCredentialFile.prepareDirectory(directory)
        for name in [".eucrante-youtube-cookies.txt", ".eucrante-site-cookies.txt"] {
          let cookie = directory.appendingPathComponent(name)
          if FileManager.default.fileExists(atPath: cookie.path) {
            try FileManager.default.removeItem(at: cookie)
          }
        }
      }
    }
  }
}
