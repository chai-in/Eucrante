import AppKit
import EucranteCore
import Foundation

enum ArtworkStore {
  static let maximumSourceBytes = 10 * 1_024 * 1_024

  static func persist(
    selectedURL: URL,
    jobID: UUID,
    rootDirectory: URL = defaultRootDirectory
  ) throws -> URL {
    let access = selectedURL.startAccessingSecurityScopedResource()
    defer {
      if access { selectedURL.stopAccessingSecurityScopedResource() }
    }

    let values = try selectedURL.resourceValues(forKeys: [
      .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
    ])
    guard values.isRegularFile == true, values.isSymbolicLink != true,
      let size = values.fileSize, size > 0, size <= maximumSourceBytes
    else {
      throw ArtworkStoreError.invalidImage
    }
    let data = try Data(contentsOf: selectedURL, options: .mappedIfSafe)
    guard let normalized = ArtworkNormalizer.jpegData(from: data) else {
      throw ArtworkStoreError.invalidImage
    }
    return try persist(normalizedJPEG: normalized, jobID: jobID, rootDirectory: rootDirectory)
  }

  static func cacheProviderArtwork(
    from url: URL,
    jobID: UUID,
    rootDirectory: URL = defaultRootDirectory
  ) async -> URL? {
    guard url.scheme?.lowercased() == "https" else { return nil }
    do {
      var request = URLRequest(url: url)
      request.timeoutInterval = 15
      let (data, response) = try await URLSession.shared.data(for: request)
      guard data.count > 0, data.count <= maximumSourceBytes,
        let http = response as? HTTPURLResponse,
        (200..<300).contains(http.statusCode),
        http.mimeType?.lowercased().hasPrefix("image/") == true,
        let normalized = ArtworkNormalizer.jpegData(from: data)
      else { return nil }
      return try persist(
        normalizedJPEG: normalized,
        jobID: jobID,
        rootDirectory: rootDirectory
      )
    } catch {
      return nil
    }
  }

  private static func persist(
    normalizedJPEG: Data,
    jobID: UUID,
    rootDirectory: URL
  ) throws -> URL {
    let directory = rootDirectory.appendingPathComponent(jobID.uuidString, isDirectory: true)
    return try SecureCredentialFile.writeAtomically(
      normalizedJPEG,
      named: "cover.jpg",
      to: directory
    )
  }

  static func remove(
    jobID: UUID,
    rootDirectory: URL = defaultRootDirectory,
    fileManager: FileManager = .default
  ) {
    try? fileManager.removeItem(
      at: rootDirectory.appendingPathComponent(jobID.uuidString, isDirectory: true))
  }

  static func validateSelection(_ url: URL) -> Bool {
    guard
      let values = try? url.resourceValues(forKeys: [
        .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
      ]), values.isRegularFile == true, values.isSymbolicLink != true,
      let size = values.fileSize, size > 0, size <= maximumSourceBytes,
      let data = try? Data(contentsOf: url, options: .mappedIfSafe)
    else { return false }
    return ArtworkNormalizer.jpegData(from: data) != nil
  }

  private static var defaultRootDirectory: URL {
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return
      base
      .appendingPathComponent("Eucrante", isDirectory: true)
      .appendingPathComponent("Artwork", isDirectory: true)
  }
}

enum ArtworkNormalizer {
  static func jpegData(from data: Data) -> Data? {
    guard !data.isEmpty, data.count <= ArtworkStore.maximumSourceBytes,
      let image = NSImage(data: data),
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff)
    else { return nil }
    return bitmap.representation(
      using: .jpeg,
      properties: [.compressionFactor: 0.95]
    )
  }
}

enum ArtworkStoreError: LocalizedError {
  case invalidImage

  var errorDescription: String? {
    "Choose a JPEG, PNG, or WebP artwork image smaller than 10 MB."
  }
}
