import Foundation

public struct DownloadProgress: Equatable, Sendable {
  public let bytesCompleted: Int64
  public let bytesExpected: Int64?

  public init(bytesCompleted: Int64, bytesExpected: Int64?) {
    self.bytesCompleted = bytesCompleted
    self.bytesExpected = bytesExpected
  }

  public var fraction: Double? {
    guard let bytesExpected, bytesExpected > 0 else { return nil }
    return min(1, max(0, Double(bytesCompleted) / Double(bytesExpected)))
  }
}

public protocol MediaDownloading: Sendable {
  func download(
    from remoteURL: URL,
    suggestedFilename: String?,
    to directory: URL,
    resumeData: Data?,
    progress: @escaping @Sendable (DownloadProgress) -> Void
  ) async throws -> SavedFile
}

extension MediaDownloading {
  public func download(
    from remoteURL: URL,
    suggestedFilename: String?,
    to directory: URL
  ) async throws -> SavedFile {
    try await download(
      from: remoteURL,
      suggestedFilename: suggestedFilename,
      to: directory,
      resumeData: nil,
      progress: { _ in }
    )
  }
}

public struct SavedFile: Equatable, Sendable {
  public let url: URL
  public let byteCount: Int64?

  public init(url: URL, byteCount: Int64?) {
    self.url = url
    self.byteCount = byteCount
  }
}

public struct DownloadService: MediaDownloading, @unchecked Sendable {
  private let injectedSession: URLSession?

  public init(session: URLSession? = nil) {
    injectedSession = session
  }

  public func download(
    from remoteURL: URL,
    suggestedFilename: String?,
    to directory: URL,
    resumeData: Data? = nil,
    progress: @escaping @Sendable (DownloadProgress) -> Void = { _ in }
  ) async throws -> SavedFile {
    guard let scheme = remoteURL.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
      throw DownloadError.unsupportedURL
    }

    if let injectedSession {
      var request = URLRequest(url: remoteURL)
      request.timeoutInterval = 60
      let (temporaryURL, response) = try await injectedSession.download(for: request)
      guard let http = response as? HTTPURLResponse else { throw DownloadError.invalidResponse }
      guard (200..<300).contains(http.statusCode) else {
        throw DownloadError.httpStatus(http.statusCode)
      }
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let preferredName =
        suggestedFilename ?? http.suggestedFilename ?? remoteURL.lastPathComponent
      let destination = FileDestinationResolver.uniqueDestination(
        for: FilenameSanitizer.sanitize(preferredName),
        in: directory
      )
      do {
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
      } catch {
        throw DownloadError.fileMove(error.localizedDescription)
      }
      let values = try? destination.resourceValues(forKeys: [.fileSizeKey])
      let byteCount = values?.fileSize.map(Int64.init)
      progress(DownloadProgress(bytesCompleted: byteCount ?? 0, bytesExpected: byteCount))
      return SavedFile(url: destination, byteCount: byteCount)
    }

    let transfer = DownloadTransfer(
      remoteURL: remoteURL,
      suggestedFilename: suggestedFilename,
      directory: directory,
      resumeData: resumeData,
      progress: progress
    )
    return try await transfer.run()
  }
}

private final class DownloadTransfer: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  private let remoteURL: URL
  private let suggestedFilename: String?
  private let directory: URL
  private let resumeData: Data?
  private let progress: @Sendable (DownloadProgress) -> Void
  private let lock = NSLock()
  private var continuation: CheckedContinuation<SavedFile, Error>?
  private var task: URLSessionDownloadTask?
  private var session: URLSession?
  private var producedResumeData: Data?
  private var finished = false

  init(
    remoteURL: URL,
    suggestedFilename: String?,
    directory: URL,
    resumeData: Data?,
    progress: @escaping @Sendable (DownloadProgress) -> Void
  ) {
    self.remoteURL = remoteURL
    self.suggestedFilename = suggestedFilename
    self.directory = directory
    self.resumeData = resumeData
    self.progress = progress
  }

  func run() async throws -> SavedFile {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        lock.withLock { self.continuation = continuation }
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        let task: URLSessionDownloadTask
        if let resumeData, !resumeData.isEmpty {
          task = session.downloadTask(withResumeData: resumeData)
        } else {
          var request = URLRequest(url: remoteURL)
          request.timeoutInterval = 60
          task = session.downloadTask(with: request)
        }
        self.task = task
        task.resume()
      }
    } onCancel: {
      cancel()
    }
  }

  private func cancel() {
    lock.withLock {
      guard !finished else { return }
      task?.cancel { [weak self] data in
        self?.lock.withLock { self?.producedResumeData = data }
      }
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
    progress(DownloadProgress(bytesCompleted: totalBytesWritten, bytesExpected: expected))
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard let http = downloadTask.response as? HTTPURLResponse else {
      finish(.failure(DownloadError.invalidResponse))
      return
    }
    guard (200..<300).contains(http.statusCode) else {
      finish(.failure(DownloadError.httpStatus(http.statusCode)))
      return
    }

    do {
      let fileManager = FileManager.default
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      let preferredName =
        suggestedFilename ?? http.suggestedFilename ?? remoteURL.lastPathComponent
      let safeName = FilenameSanitizer.sanitize(preferredName)
      let destination = FileDestinationResolver.uniqueDestination(
        for: safeName,
        in: directory,
        fileManager: fileManager
      )
      try fileManager.moveItem(at: location, to: destination)
      let values = try? destination.resourceValues(forKeys: [.fileSizeKey])
      finish(
        .success(SavedFile(url: destination, byteCount: values?.fileSize.map(Int64.init))))
    } catch {
      finish(.failure(DownloadError.fileMove(error.localizedDescription)))
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard let error else { return }
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
      let data =
        producedResumeData
        ?? nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
      finish(.failure(DownloadError.cancelled(data)))
    } else {
      finish(.failure(DownloadError.transport(error.localizedDescription)))
    }
  }

  private func finish(_ result: Result<SavedFile, Error>) {
    let continuation: CheckedContinuation<SavedFile, Error>? = lock.withLock {
      guard !finished else { return nil }
      finished = true
      let value = self.continuation
      self.continuation = nil
      return value
    }
    session?.finishTasksAndInvalidate()
    continuation?.resume(with: result)
  }
}

public enum FileDestinationResolver {
  public static func uniqueDestination(
    for filename: String,
    in directory: URL,
    fileManager: FileManager = .default
  ) -> URL {
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
      if !fileManager.fileExists(atPath: candidate.path) { return candidate }
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
  case transport(String)
  case fileMove(String)
  case cancelled(Data?)

  public var resumeData: Data? {
    if case .cancelled(let data) = self { return data }
    return nil
  }

  public var errorDescription: String? {
    switch self {
    case .unsupportedURL: "The download URL is not HTTP or HTTPS."
    case .invalidResponse: "The download returned an invalid response."
    case .httpStatus(let code): "The download returned HTTP \(code)."
    case .transport: "The download was interrupted. Try again to resume it."
    case .fileMove: "The downloaded file could not be moved into the destination folder."
    case .cancelled: "The download was cancelled."
    }
  }
}

extension NSLock {
  fileprivate func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock()
    defer { unlock() }
    return try body()
  }
}
