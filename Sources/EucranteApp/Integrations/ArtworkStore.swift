import EucranteCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ArtworkStore {
  static let maximumSourceBytes = 10 * 1_024 * 1_024

  static func persist(
    selectedURL: URL,
    jobID: UUID,
    style: CoverStyle = .original,
    removeBlackBars: Bool = true,
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
    guard
      let normalized = ArtworkNormalizer.jpegData(
        from: data, style: style, removeBlackBars: removeBlackBars)
    else {
      throw ArtworkStoreError.invalidImage
    }
    return try persist(normalizedJPEG: normalized, jobID: jobID, rootDirectory: rootDirectory)
  }

  static func cacheProviderArtwork(
    from url: URL,
    jobID: UUID,
    style: CoverStyle = .original,
    removeBlackBars: Bool = true,
    rootDirectory: URL = defaultRootDirectory
  ) async -> URL? {
    guard url.scheme?.lowercased() == "https" else { return nil }
    do {
      let data = try await download(from: url)
      guard
        let normalized = ArtworkNormalizer.jpegData(
          from: data, style: style, removeBlackBars: removeBlackBars)
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

  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 30
    return URLSession(configuration: configuration)
  }()

  static func download(from url: URL, session: URLSession = session) async throws -> Data {
    guard url.scheme?.lowercased() == "https" else { throw ArtworkStoreError.invalidImage }
    let (bytes, response) = try await session.bytes(from: url)
    // Also cancel on header rejection, oversized chunked responses, and task cancellation.
    defer { bytes.task.cancel() }
    guard let http = response as? HTTPURLResponse,
      http.url?.scheme?.lowercased() == "https",
      (200..<300).contains(http.statusCode),
      http.mimeType?.lowercased().hasPrefix("image/") == true,
      response.expectedContentLength <= Int64(maximumSourceBytes)
    else { throw ArtworkStoreError.invalidImage }
    var data = Data()
    data.reserveCapacity(Int(max(0, response.expectedContentLength)))
    for try await byte in bytes {
      guard data.count < maximumSourceBytes else { throw ArtworkStoreError.invalidImage }
      data.append(byte)
    }
    try Task.checkCancellation()
    guard !data.isEmpty else { throw ArtworkStoreError.invalidImage }
    return data
  }

  private static func persist(
    normalizedJPEG: Data,
    jobID: UUID,
    style: CoverStyle = .original,
    removeBlackBars: Bool = true,
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
    style: CoverStyle = .original,
    removeBlackBars: Bool = true,
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
  static let maximumPixelSize = 2_048

  static func jpegData(from data: Data, style: CoverStyle = .original, removeBlackBars: Bool = true)
    -> Data?
  {
    guard !data.isEmpty, data.count <= ArtworkStore.maximumSourceBytes,
      let source = CGImageSourceCreateWithData(
        data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
          kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    else { return nil }
    guard let rendered = CoverRenderer.render(image, style: style, removeBlackBars: removeBlackBars)
    else { return nil }
    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output, UTType.jpeg.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(
      destination, rendered, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return output as Data
  }
}

enum ArtworkStoreError: LocalizedError {
  case invalidImage

  var errorDescription: String? {
    "Choose a JPEG, PNG, or WebP artwork image smaller than 10 MB."
  }
}
