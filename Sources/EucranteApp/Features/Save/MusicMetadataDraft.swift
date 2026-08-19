import EucranteCore
import Foundation

struct MusicMetadataDraft: Equatable {
  var title = ""
  var artist = ""
  var album = ""
  var albumArtist = ""
  var composer = ""
  var genre = ""
  var year = ""
  var trackNumber = ""
  var discNumber = ""
  var artworkURL: URL?

  var isEmpty: Bool {
    [title, artist, album, albumArtist, composer, genre, year, trackNumber, discNumber]
      .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      && artworkURL == nil
  }

  func metadata() throws -> MediaMetadata? {
    guard !isEmpty else { return nil }
    return MediaMetadata(
      title: text(title),
      artist: text(artist),
      album: text(album),
      albumArtist: text(albumArtist),
      composer: text(composer),
      genre: text(genre),
      year: try positiveNumber(year, label: "Year"),
      trackNumber: try positiveNumber(trackNumber, label: "Track number"),
      discNumber: try positiveNumber(discNumber, label: "Disc number"),
      artworkURL: artworkURL
    )
  }

  private func text(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func positiveNumber(_ value: String, label: String) throws -> Int? {
    guard let text = text(value) else { return nil }
    guard let number = Int(text), number > 0 else {
      throw MusicMetadataDraftError.invalidNumber(label)
    }
    return number
  }
}

enum MusicMetadataDraftError: LocalizedError {
  case invalidNumber(String)

  var errorDescription: String? {
    switch self {
    case .invalidNumber(let label):
      "\(label) must be a positive whole number."
    }
  }
}
