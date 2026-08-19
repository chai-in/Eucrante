import Foundation

public struct MediaMetadata: Codable, Equatable, Sendable {
  public var title: String?
  public var artist: String?
  public var album: String?
  public var albumArtist: String?
  public var composer: String?
  public var genre: String?
  public var year: Int?
  public var trackNumber: Int?
  public var trackCount: Int?
  public var discNumber: Int?
  public var discCount: Int?
  public var description: String?
  public var sourceID: String?
  public var sourceURL: URL?
  public var artworkURL: URL?

  public init(
    title: String? = nil,
    artist: String? = nil,
    album: String? = nil,
    albumArtist: String? = nil,
    composer: String? = nil,
    genre: String? = nil,
    year: Int? = nil,
    trackNumber: Int? = nil,
    trackCount: Int? = nil,
    discNumber: Int? = nil,
    discCount: Int? = nil,
    description: String? = nil,
    sourceID: String? = nil,
    sourceURL: URL? = nil,
    artworkURL: URL? = nil
  ) {
    self.title = title
    self.artist = artist
    self.album = album
    self.albumArtist = albumArtist
    self.composer = composer
    self.genre = genre
    self.year = year
    self.trackNumber = trackNumber
    self.trackCount = trackCount
    self.discNumber = discNumber
    self.discCount = discCount
    self.description = description
    self.sourceID = sourceID
    self.sourceURL = sourceURL
    self.artworkURL = artworkURL
  }

  public var hasMusicDetails: Bool {
    [title, artist, album, albumArtist, composer, genre, description, sourceID]
      .contains { $0?.isEmpty == false }
      || year != nil || trackNumber != nil || discNumber != nil || artworkURL != nil
  }
}
