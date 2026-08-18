import AppKit
import Foundation

@MainActor
struct MusicLibraryImporter {
  func importFile(at url: URL) throws {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw MusicImportError.missingFile
    }

    let escapedPath = url.path
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    let source = """
      tell application "Music"
        launch
        add POSIX file "\(escapedPath)"
      end tell
      """
    guard let script = NSAppleScript(source: source) else {
      throw MusicImportError.scriptUnavailable
    }

    var details: NSDictionary?
    let result = script.executeAndReturnError(&details)
    if let details {
      let message = details["NSAppleScriptErrorMessage"] as? String
      throw MusicImportError.rejected(message ?? "Music did not accept the file.")
    }
    guard result.descriptorType != 0 else {
      throw MusicImportError.rejected("Music did not confirm the import.")
    }
  }
}

enum MusicImportError: LocalizedError {
  case missingFile
  case scriptUnavailable
  case rejected(String)

  var errorDescription: String? {
    switch self {
    case .missingFile:
      "The finished audio file is no longer on this Mac."
    case .scriptUnavailable:
      "Eucrante could not prepare the Music import."
    case .rejected(let message):
      "Music could not import the file: \(message)"
    }
  }
}
