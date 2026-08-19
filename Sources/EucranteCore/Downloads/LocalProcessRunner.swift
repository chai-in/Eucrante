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
      guard process.isRunning else { return }
      Darwin.kill(process.processIdentifier, SIGKILL)
    }
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
    let running = CancellableProcess(process)

    return try await withTaskCancellationHandler {
      do {
        try process.run()
      } catch {
        throw LocalAcquisitionError.toolsMissing
      }

      var captured = BoundedLineBuffer(capacity: Self.maximumCapturedLines)
      for try await line in pipe.fileHandleForReading.bytes.lines {
        captured.append(line)
        onLine(line)
      }
      process.waitUntilExit()
      try Task.checkCancellation()
      guard process.terminationReason == .exit, process.terminationStatus == 0 else {
        throw LocalMediaAcquirer.processError(
          status: process.terminationStatus,
          diagnostic: captured.lines.joined(separator: "\n")
        )
      }
      return captured.lines
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
