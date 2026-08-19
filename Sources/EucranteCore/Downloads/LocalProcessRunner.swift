import Darwin
@preconcurrency import Foundation

struct BoundedLineBuffer: Sendable {
  private let capacity: Int
  private var values: [String] = []

  init(capacity: Int) {
    self.capacity = max(1, capacity)
  }

  mutating func append(_ value: String) {
    if values.count == capacity {
      values.removeFirst()
    }
    values.append(value)
  }

  var lines: [String] { values }
}

final class CancellableProcess: @unchecked Sendable {
  private let process: Process
  private let escalationDelay: Duration
  private let lock = NSLock()
  private var cancellationRequested = false

  init(_ process: Process, escalationDelay: Duration = .milliseconds(750)) {
    self.process = process
    self.escalationDelay = escalationDelay
  }

  func cancel() {
    lock.lock()
    guard !cancellationRequested else {
      lock.unlock()
      return
    }
    cancellationRequested = true
    lock.unlock()

    if process.isRunning {
      process.terminate()
    }
    Task.detached(priority: .utility) { [self] in
      try? await Task.sleep(for: escalationDelay)
      if process.isRunning {
        Darwin.kill(process.processIdentifier, SIGKILL)
      }
    }
  }
}

final class ProcessTerminationWaiter: @unchecked Sendable {
  private let lock = NSLock()
  private var finished = false
  private var continuation: CheckedContinuation<Void, Never>?

  func signal() {
    let waiting = lock.withLock { () -> CheckedContinuation<Void, Never>? in
      guard !finished else { return nil }
      finished = true
      defer { continuation = nil }
      return continuation
    }
    waiting?.resume()
  }

  func wait() async {
    await withCheckedContinuation { continuation in
      let resumeImmediately = lock.withLock { () -> Bool in
        if finished { return true }
        self.continuation = continuation
        return false
      }
      if resumeImmediately { continuation.resume() }
    }
  }
}

final class ProcessLineReader: @unchecked Sendable {
  private let ioLock = NSLock()
  private let stateLock = NSLock()
  private let onLine: @Sendable (String) -> Void
  private var pending = Data()
  private var captured: BoundedLineBuffer
  private var closed = false

  init(capacity: Int, onLine: @escaping @Sendable (String) -> Void) {
    captured = BoundedLineBuffer(capacity: capacity)
    self.onLine = onLine
  }

  func readAvailableData(from handle: FileHandle) {
    ioLock.withLock {
      guard !closed else { return }
      let data = handle.availableData
      if !data.isEmpty { consume(data) }
    }
  }

  func finish(reading handle: FileHandle) -> [String] {
    ioLock.withLock {
      guard !closed else { return }
      closed = true
      let descriptor = handle.fileDescriptor
      let flags = Darwin.fcntl(descriptor, F_GETFL)
      if flags >= 0 {
        _ = Darwin.fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
      }
      let remaining = handle.availableData
      if !remaining.isEmpty { consume(remaining) }
      try? handle.close()
    }
    var finalLine: String?
    let lines = stateLock.withLock {
      if !pending.isEmpty {
        let line = String(decoding: pending, as: UTF8.self)
        captured.append(line)
        finalLine = line
        pending.removeAll(keepingCapacity: false)
      }
      return captured.lines
    }
    if let finalLine { onLine(finalLine) }
    return lines
  }

  private func consume(_ data: Data) {
    let lines = stateLock.withLock { () -> [String] in
      pending.append(data)
      var values: [String] = []
      while let newline = pending.firstIndex(of: 0x0A) {
        var line = Data(pending[pending.startIndex..<newline])
        pending.removeSubrange(pending.startIndex...newline)
        if line.last == 0x0D { line.removeLast() }
        values.append(String(decoding: line, as: UTF8.self))
      }
      for value in values { captured.append(value) }
      return values
    }
    for line in lines { onLine(line) }
  }
}

actor LocalProcessRunner {
  static let maximumCapturedLines = 200

  func run(
    executable: URL,
    arguments: [String],
    environment: [String: String]? = nil,
    onLine: @escaping @Sendable (String) -> Void
  ) async throws -> [String] {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe
    process.environment =
      environment
      ?? Self.restrictedEnvironment(homeDirectory: FileManager.default.temporaryDirectory)
    let termination = ProcessTerminationWaiter()
    let reader = ProcessLineReader(capacity: Self.maximumCapturedLines, onLine: onLine)
    pipe.fileHandleForReading.readabilityHandler = { handle in
      reader.readAvailableData(from: handle)
    }
    process.terminationHandler = { _ in termination.signal() }
    let running = CancellableProcess(process)

    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      do {
        try process.run()
      } catch {
        pipe.fileHandleForReading.readabilityHandler = nil
        _ = reader.finish(reading: pipe.fileHandleForReading)
        throw LocalAcquisitionError.toolsMissing
      }
      try? pipe.fileHandleForWriting.close()
      await termination.wait()
      pipe.fileHandleForReading.readabilityHandler = nil
      let captured = reader.finish(reading: pipe.fileHandleForReading)
      try Task.checkCancellation()
      guard process.terminationReason == .exit, process.terminationStatus == 0 else {
        throw LocalMediaAcquirer.processError(
          status: process.terminationStatus,
          diagnostic: captured.joined(separator: "\n")
        )
      }
      return captured
    } onCancel: {
      running.cancel()
    }
  }

  nonisolated static func restrictedEnvironment(homeDirectory: URL) -> [String: String] {
    [
      "HOME": homeDirectory.path,
      "XDG_CONFIG_HOME": homeDirectory.appendingPathComponent(".config").path,
      "XDG_CACHE_HOME": homeDirectory.appendingPathComponent(".cache").path,
      "DENO_DIR": homeDirectory.appendingPathComponent(".deno").path,
      "TMPDIR": homeDirectory.appendingPathComponent(".tmp").path,
      "LANG": "en_US.UTF-8",
      "LC_ALL": "en_US.UTF-8",
      "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
    ]
  }

  nonisolated static func prepareRestrictedEnvironment(
    homeDirectory: URL,
    fileManager: FileManager = .default
  ) throws {
    try SecureCredentialFile.prepareDirectory(homeDirectory, fileManager: fileManager)
    for component in [".config", ".cache", ".deno", ".tmp"] {
      try SecureCredentialFile.prepareDirectory(
        homeDirectory.appendingPathComponent(component, isDirectory: true),
        fileManager: fileManager
      )
    }
  }
}
