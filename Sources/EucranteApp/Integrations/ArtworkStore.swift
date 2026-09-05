import EucranteCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

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
      let data = try await download(from: url)
      guard
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
    let transfer = ArtworkTransfer()
    let data = try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        transfer.start(session.dataTask(with: url), continuation: continuation)
      }
    } onCancel: {
      transfer.cancel()
    }
    try Task.checkCancellation()
    return data
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
    return ArtworkNormalizer.thumbnail(from: data, maximumPixelSize: 1) != nil
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

// URLSession delivers bounded chunks on its delegate queue. Per-task delegates keep the
// shared ephemeral session's connection reuse without a suspension and Data append per byte.
private final class ArtworkTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private var task: URLSessionDataTask?
  private var continuation: CheckedContinuation<Data, Error>?
  private var result: Result<Data, Error>?
  private var completed = false
  private var data = Data()

  func start(_ task: URLSessionDataTask, continuation: CheckedContinuation<Data, Error>) {
    let earlyResult = lock.withLock { () -> Result<Data, Error>? in
      if completed { return result }
      self.task = task
      self.continuation = continuation
      task.delegate = self
      return nil
    }
    if let earlyResult {
      task.cancel()
      continuation.resume(with: earlyResult)
    } else {
      task.resume()
    }
  }

  func cancel() {
    finish(.failure(CancellationError()))
  }

  private func finish(_ result: Result<Data, Error>) {
    let waiting = lock.withLock { () -> (URLSessionDataTask?, CheckedContinuation<Data, Error>?) in
      guard !completed else { return (nil, nil) }
      completed = true
      if continuation == nil { self.result = result }
      defer {
        task = nil
        continuation = nil
        data = Data()
      }
      return (task, continuation)
    }
    waiting.0?.cancel()
    waiting.1?.resume(with: result)
  }

  func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
  ) {
    guard let http = response as? HTTPURLResponse,
      http.url?.scheme?.lowercased() == "https", (200..<300).contains(http.statusCode),
      http.mimeType?.lowercased().hasPrefix("image/") == true,
      response.expectedContentLength <= Int64(ArtworkStore.maximumSourceBytes)
    else {
      finish(.failure(ArtworkStoreError.invalidImage))
      completionHandler(.cancel)
      return
    }
    lock.withLock {
      if !completed { data.reserveCapacity(Int(max(0, response.expectedContentLength))) }
    }
    completionHandler(.allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
    let oversized = lock.withLock {
      guard !completed else { return false }
      guard chunk.count <= ArtworkStore.maximumSourceBytes - data.count else { return true }
      data.append(chunk)
      return false
    }
    if oversized { finish(.failure(ArtworkStoreError.invalidImage)) }
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    guard request.url?.scheme?.lowercased() == "https" else {
      finish(.failure(ArtworkStoreError.invalidImage))
      completionHandler(nil)
      return
    }
    completionHandler(request)
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
  ) {
    let result: Result<Data, Error> = lock.withLock {
      if let error { return .failure(error) }
      return data.isEmpty ? .failure(ArtworkStoreError.invalidImage) : .success(data)
    }
    finish(result)
  }
}

enum ArtworkNormalizer {
  static let maximumPixelSize = 2_048

  static func jpegData(from data: Data) -> Data? {
    guard let image = thumbnail(from: data, maximumPixelSize: maximumPixelSize) else { return nil }
    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output, UTType.jpeg.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(
      destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return output as Data
  }

  static func jpegForImport(from data: Data) -> Data? {
    // Stored covers are already normalized. Preserve their exact JPEG bytes on Music import
    // instead of paying for another full decode/encode and another lossy JPEG generation.
    if data.count <= ArtworkStore.maximumSourceBytes,
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetType(source) as String? == UTType.jpeg.identifier,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0, max(width, height) <= maximumPixelSize,
      (properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1,
      thumbnail(from: data, maximumPixelSize: 1) != nil
    {
      return data
    }
    return jpegData(from: data)
  }

  static func thumbnail(from data: Data, maximumPixelSize: Int) -> CGImage? {
    guard !data.isEmpty, data.count <= ArtworkStore.maximumSourceBytes,
      let source = CGImageSourceCreateWithData(
        data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
    else { return nil }
    return CGImageSourceCreateThumbnailAtIndex(
      source, 0,
      [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        kCGImageSourceShouldCacheImmediately: true,
      ] as CFDictionary)
  }
}

enum ArtworkStoreError: LocalizedError {
  case invalidImage

  var errorDescription: String? {
    "Choose a JPEG, PNG, or WebP artwork image smaller than 10 MB."
  }
}
