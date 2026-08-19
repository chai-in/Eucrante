@preconcurrency import Foundation

public enum AppleVideoTranscodeQuality: String, Codable, Equatable, Sendable {
  case best
  case efficient

  fileprivate var videoToolboxQuality: Int {
    switch self {
    case .best: 75
    case .efficient: 58
    }
  }
}

public actor AppleVideoTranscoder {
  private let executable: URL
  private let fileManager: FileManager

  public init(
    executable: URL = LocalMediaAcquirer.ToolPaths.discover().ffmpeg,
    fileManager: FileManager = .default
  ) {
    self.executable = executable
    self.fileManager = fileManager
  }

  public func transcode(
    video: URL,
    audio: URL?,
    duration: Double?,
    quality: AppleVideoTranscodeQuality,
    workingDirectory: URL,
    progress: @escaping @Sendable (Double) -> Void = { _ in }
  ) async throws -> URL {
    guard fileManager.isExecutableFile(atPath: executable.path) else {
      throw AppleVideoTranscodeError.toolMissing
    }
    try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
    let output = workingDirectory.appendingPathComponent("apple-hevc.mp4")
    if fileManager.fileExists(atPath: output.path) {
      try fileManager.removeItem(at: output)
    }

    let arguments = Self.arguments(
      video: video,
      audio: audio,
      output: output,
      quality: quality
    )
    let process = Process()
    let processPipe = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = processPipe
    process.standardError = processPipe
    process.environment = [
      "HOME": fileManager.homeDirectoryForCurrentUser.path,
      "LANG": "en_US.UTF-8",
      "LC_ALL": "en_US.UTF-8",
      "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
    ]
    let running = TranscodingProcess(process)

    do {
      try await withTaskCancellationHandler {
        do {
          try process.run()
        } catch {
          throw AppleVideoTranscodeError.toolMissing
        }
        progress(0)
        var diagnosticLines: [String] = []
        for try await line in processPipe.fileHandleForReading.bytes.lines {
          if let outTime = Self.parseProgressTime(line), let duration, duration > 0 {
            progress(min(0.99, max(0, outTime / duration)))
          } else if diagnosticLines.count < 100 {
            diagnosticLines.append(line)
          }
        }
        process.waitUntilExit()
        try Task.checkCancellation()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
          throw AppleVideoTranscodeError.failed(
            diagnosticLines.suffix(20).joined(separator: "\n")
              .trimmingCharacters(in: .whitespacesAndNewlines)
          )
        }
      } onCancel: {
        running.cancel()
      }
    } catch {
      try? fileManager.removeItem(at: output)
      throw error
    }

    guard
      let values = try? output.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
      values.isRegularFile == true,
      (values.fileSize ?? 0) > 0
    else {
      throw AppleVideoTranscodeError.outputMissing
    }
    progress(1)
    return output
  }

  static func arguments(
    video: URL,
    audio: URL?,
    output: URL,
    quality: AppleVideoTranscodeQuality
  ) -> [String] {
    var values = [
      "-hide_banner", "-loglevel", "error", "-nostats", "-nostdin", "-y",
      "-i", video.path,
    ]
    if let audio {
      values.append(contentsOf: ["-i", audio.path])
    }
    values.append(contentsOf: ["-map", "0:v:0"])
    if audio != nil {
      values.append(contentsOf: ["-map", "1:a:0"])
    }
    values.append(contentsOf: [
      "-c:v", "hevc_videotoolbox",
      "-allow_sw", "0",
      "-q:v", String(quality.videoToolboxQuality),
      "-tag:v", "hvc1",
    ])
    if audio != nil {
      values.append(contentsOf: ["-c:a", "copy", "-shortest"])
    }
    values.append(contentsOf: [
      "-movflags", "+faststart",
      "-progress", "pipe:1",
      output.path,
    ])
    return values
  }

  static func parseProgressTime(_ line: String) -> Double? {
    if line.hasPrefix("out_time_us=") {
      return Double(line.dropFirst("out_time_us=".count)).map { $0 / 1_000_000 }
    }
    if line.hasPrefix("out_time_ms=") {
      return Double(line.dropFirst("out_time_ms=".count)).map { $0 / 1_000_000 }
    }
    return nil
  }
}

private final class TranscodingProcess: @unchecked Sendable {
  let process: Process

  init(_ process: Process) { self.process = process }

  func cancel() {
    if process.isRunning { process.terminate() }
  }
}

public enum AppleVideoTranscodeError: LocalizedError, Equatable, Sendable {
  case toolMissing
  case failed(String)
  case outputMissing

  public var errorDescription: String? {
    switch self {
    case .toolMissing:
      "Eucrante's Apple video converter is missing or damaged. Reinstall the app."
    case .failed(let detail):
      detail.isEmpty
        ? "The Apple hardware video conversion could not finish."
        : "The Apple hardware video conversion could not finish: \(detail)"
    case .outputMissing:
      "The Apple hardware video conversion produced no usable file."
    }
  }
}
