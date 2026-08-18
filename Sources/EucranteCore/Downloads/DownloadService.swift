import Foundation

public protocol MediaDownloading: Sendable {
  func download(
    from remoteURL: URL,
    suggestedFilename: String?,
    to directory: URL
  ) async throws -> SavedFile
}

public struct SavedFile: Equatable, Sendable {
  public let url: URL
  public let byteCount: Int64?

  public init(url: URL, byteCount: Int64?) {
    self.url = url
    self.byteCount = byteCount
  }
}

public actor DownloadService: MediaDownloading {
  private let session: URLSession
  private let fileManager: FileManager

  public init(session: URLSession = .shared, fileManager: FileManager = .default) {
    self.session = session
    self.fileManager = fileManager
  }

  public func download(
    from remoteURL: URL,
    suggestedFilename: String?,
    to directory: URL
  ) async throws -> SavedFile {
    guard let scheme = remoteURL.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
      throw DownloadError.unsupportedURL
    }

    var request = URLRequest(url: remoteURL)
    request.timeoutInterval = 60
    let (temporaryURL, response) = try await session.download(for: request)

    guard let http = response as? HTTPURLResponse else {
      throw DownloadError.invalidResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      throw DownloadError.httpStatus(http.statusCode)
    }

    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

    let preferredName = suggestedFilename ?? http.suggestedFilename ?? remoteURL.lastPathComponent
    let safeName = FilenameSanitizer.sanitize(preferredName)
    let destination = uniqueDestination(for: safeName, in: directory)

    do {
      try fileManager.moveItem(at: temporaryURL, to: destination)
    } catch {
      throw DownloadError.fileMove(error.localizedDescription)
    }

    let values = try? destination.resourceValues(forKeys: [.fileSizeKey])
    return SavedFile(url: destination, byteCount: values?.fileSize.map(Int64.init))
  }

  private func uniqueDestination(for filename: String, in directory: URL) -> URL {
    let proposed = directory.appendingPathComponent(filename, isDirectory: false)
    guard fileManager.fileExists(atPath: proposed.path) else { return proposed }

    let extensionName = proposed.pathExtension
    let stem = proposed.deletingPathExtension().lastPathComponent

    for suffix in 2...9_999 {
      let candidateName =
        extensionName.isEmpty
        ? "\(stem) \(suffix)"
        : "\(stem) \(suffix).\(extensionName)"
      let candidate = directory.appendingPathComponent(candidateName, isDirectory: false)
      if !fileManager.fileExists(atPath: candidate.path) {
        return candidate
      }
    }

    return directory.appendingPathComponent(
      UUID().uuidString + (extensionName.isEmpty ? "" : ".\(extensionName)"))
  }
}

public enum FilenameSanitizer {
  public static func sanitize(_ input: String, maximumLength: Int = 180) -> String {
    var value =
      input
      .replacingOccurrences(of: "\\", with: "-")
      .replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: ":", with: "-")

    value.unicodeScalars.removeAll { scalar in
      CharacterSet.controlCharacters.contains(scalar)
    }

    value = value.trimmingCharacters(
      in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
    guard !value.isEmpty, value != ".", value != ".." else { return "download" }

    guard value.count > maximumLength else { return value }

    let sourceURL = URL(fileURLWithPath: value)
    let ext = sourceURL.pathExtension
    let extensionBudget = ext.isEmpty ? 0 : ext.count + 1
    let stemBudget = max(1, maximumLength - extensionBudget)
    let stem = String(sourceURL.deletingPathExtension().lastPathComponent.prefix(stemBudget))
    return ext.isEmpty ? stem : "\(stem).\(ext)"
  }
}

public enum DownloadError: LocalizedError, Equatable, Sendable {
  case unsupportedURL
  case invalidResponse
  case httpStatus(Int)
  case fileMove(String)

  public var errorDescription: String? {
    switch self {
    case .unsupportedURL:
      "The download URL is not HTTP or HTTPS."
    case .invalidResponse:
      "The download returned an invalid response."
    case .httpStatus(let code):
      "The download returned HTTP \(code)."
    case .fileMove:
      "The downloaded file could not be moved into the destination folder."
    }
  }
}
