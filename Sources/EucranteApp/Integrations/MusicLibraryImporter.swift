import AppKit
import EucranteCore
import Foundation

@MainActor
struct MusicLibraryImporter {
  func importFile(at url: URL, metadata: MediaMetadata?) async throws {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw MusicImportError.missingFile
    }

    let artwork = await temporaryArtwork(for: metadata?.artworkURL)
    defer {
      if let artwork {
        try? FileManager.default.removeItem(at: artwork.deletingLastPathComponent())
      }
    }
    let source = Self.scriptSource(
      fileURL: url,
      metadata: metadata,
      artworkURL: artwork
    )
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

  static func scriptSource(
    fileURL: URL,
    metadata: MediaMetadata?,
    artworkURL: URL?
  ) -> String {
    var assignments: [String] = []
    func setText(_ property: String, _ value: String?) {
      guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
      else { return }
      assignments.append("set \(property) of importedTrack to \(literal(value))")
    }
    func setNumber(_ property: String, _ value: Int?) {
      guard let value, value >= 0 else { return }
      assignments.append("set \(property) of importedTrack to \(value)")
    }

    setText("name", metadata?.title)
    setText("artist", metadata?.artist)
    setText("album", metadata?.album)
    setText("album artist", metadata?.albumArtist)
    setText("composer", metadata?.composer)
    setText("genre", metadata?.genre)
    setText("description", metadata?.description)
    setNumber("year", metadata?.year)
    setNumber("track number", metadata?.trackNumber)
    setNumber("track count", metadata?.trackCount)
    setNumber("disc number", metadata?.discNumber)
    setNumber("disc count", metadata?.discCount)
    let commentParts = [
      metadata?.sourceURL.map { "Source: \($0.absoluteString)" },
      metadata?.sourceID.map { "Source ID: \($0)" },
    ].compactMap { $0 }
    if !commentParts.isEmpty {
      setText("comment", commentParts.joined(separator: "\n"))
    }

    if let artworkURL {
      assignments.append(
        """
        try
          set artworkData to (read POSIX file \(literal(artworkURL.path)) as picture)
          try
            set data of artwork 1 of importedTrack to artworkData
          on error
            make new artwork at importedTrack with properties {data:artworkData}
          end try
        end try
        """
      )
    }

    let body = assignments.map { "    \($0)" }.joined(separator: "\n")
    return """
      tell application "Music"
        launch
        set addedTracks to (add POSIX file \(literal(fileURL.path)))
        if class of addedTracks is list then
          set importedTrack to item 1 of addedTracks
        else
          set importedTrack to addedTracks
        end if
      \(body)
        return database ID of importedTrack
      end tell
      """
  }

  private static func literal(_ value: String) -> String {
    let escaped =
      value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .replacingOccurrences(of: "\n", with: "\\n")
    return "\"\(escaped)\""
  }

  private func temporaryArtwork(for remoteURL: URL?) async -> URL? {
    guard let remoteURL, remoteURL.scheme?.lowercased() == "https" else { return nil }
    do {
      var request = URLRequest(url: remoteURL)
      request.timeoutInterval = 15
      let (data, response) = try await URLSession.shared.data(for: request)
      guard data.count > 0, data.count <= 10 * 1_024 * 1_024,
        let http = response as? HTTPURLResponse,
        (200..<300).contains(http.statusCode),
        let mimeType = http.mimeType?.lowercased(),
        ["image/jpeg", "image/png"].contains(mimeType)
      else { return nil }
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "eucrante-artwork-\(UUID().uuidString)", isDirectory: true)
      let fileExtension = mimeType == "image/png" ? "png" : "jpg"
      return try SecureCredentialFile.write(
        data,
        named: "cover.\(fileExtension)",
        to: directory
      )
    } catch {
      return nil
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
