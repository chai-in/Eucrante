import Foundation

public enum OutputFolderBookmark {
  public static func create(for url: URL) throws -> Data {
    do {
      return try url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: [.isDirectoryKey],
        relativeTo: nil
      )
    } catch {
      throw OutputFolderError.create(error.localizedDescription)
    }
  }

  public static func resolve(_ data: Data) throws -> (url: URL, stale: Bool) {
    var stale = false
    do {
      let url = try URL(
        resolvingBookmarkData: data,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &stale
      )
      return (url, stale)
    } catch {
      throw OutputFolderError.resolve(error.localizedDescription)
    }
  }
}

public enum OutputFolderError: LocalizedError, Equatable, Sendable {
  case create(String)
  case resolve(String)

  public var errorDescription: String? {
    switch self {
    case .create: "Eucrante could not remember the selected output folder."
    case .resolve: "The selected output folder is no longer available. Choose it again."
    }
  }
}
