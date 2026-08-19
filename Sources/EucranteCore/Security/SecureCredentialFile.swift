import Darwin
import Foundation

public enum SecureCredentialFile {
  public static func prepareDirectory(
    _ directory: URL,
    fileManager: FileManager = .default
  ) throws {
    do {
      try fileManager.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    } catch {
      throw SecureCredentialFileError.fileSystem(error.localizedDescription)
    }
  }

  public static func writeAtomically(
    _ contents: Data,
    named filename: String,
    to directory: URL,
    fileManager: FileManager = .default
  ) throws -> URL {
    try validate(filename)
    let temporaryName = ".\(filename).\(UUID().uuidString).tmp"
    let temporary = try write(
      contents,
      named: temporaryName,
      to: directory,
      fileManager: fileManager
    )
    defer { try? fileManager.removeItem(at: temporary) }

    let destination = directory.appendingPathComponent(filename, isDirectory: false)
    guard Darwin.rename(temporary.path, destination.path) == 0 else {
      throw SecureCredentialFileError.fileSystem(String(cString: strerror(errno)))
    }
    do {
      try fileManager.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: destination.path
      )
      return destination
    } catch {
      throw SecureCredentialFileError.fileSystem(error.localizedDescription)
    }
  }

  public static func write(
    _ contents: Data,
    named filename: String,
    to directory: URL,
    fileManager: FileManager = .default
  ) throws -> URL {
    try validate(filename)

    do {
      try prepareDirectory(directory, fileManager: fileManager)

      let file = directory.appendingPathComponent(filename, isDirectory: false)
      if fileManager.fileExists(atPath: file.path) {
        try fileManager.removeItem(at: file)
      }
      guard
        fileManager.createFile(
          atPath: file.path,
          contents: nil,
          attributes: [.posixPermissions: 0o600]
        )
      else {
        throw SecureCredentialFileError.create
      }

      do {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.write(contentsOf: contents)
        try handle.synchronize()
      } catch {
        try? fileManager.removeItem(at: file)
        throw error
      }

      try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
      return file
    } catch let error as SecureCredentialFileError {
      throw error
    } catch {
      throw SecureCredentialFileError.fileSystem(error.localizedDescription)
    }
  }

  private static func validate(_ filename: String) throws {
    guard filename == URL(fileURLWithPath: filename).lastPathComponent,
      !filename.isEmpty,
      filename != ".",
      filename != ".."
    else {
      throw SecureCredentialFileError.invalidFilename
    }
  }
}

public enum SecureCredentialFileError: LocalizedError, Equatable, Sendable {
  case invalidFilename
  case create
  case fileSystem(String)

  public var errorDescription: String? {
    switch self {
    case .invalidFilename: "The temporary credential filename was invalid."
    case .create: "Eucrante could not create its protected temporary credential file."
    case .fileSystem: "Eucrante could not protect its temporary credential file."
    }
  }
}
