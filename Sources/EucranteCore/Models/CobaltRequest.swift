import Foundation

public struct CobaltRequest: Codable, Equatable, Sendable {
  public let url: String
  public let audioBitrate: AudioBitrate
  public let audioFormat: AudioFormat
  public let downloadMode: DownloadMode
  public let filenameStyle: FilenameStyle
  public let videoQuality: VideoQuality
  public let disableMetadata: Bool
  public let alwaysProxy: Bool
  public let localProcessing: LocalProcessingPreference
  public let subtitleLang: String?
  public let youtubeVideoCodec: YouTubeVideoCodec
  public let youtubeVideoContainer: YouTubeVideoContainer
  public let youtubeDubLang: String?
  public let convertGif: Bool
  public let allowH265: Bool
  public let tiktokFullAudio: Bool
  public let youtubeBetterAudio: Bool

  public init(sourceURL: URL, preferences: DownloadPreferences = .init()) {
    url = sourceURL.absoluteString
    audioBitrate = preferences.audioBitrate
    audioFormat = preferences.audioFormat
    downloadMode = preferences.downloadMode
    filenameStyle = preferences.filenameStyle
    videoQuality = preferences.videoQuality
    disableMetadata = preferences.disableMetadata
    alwaysProxy = preferences.alwaysProxy
    localProcessing = preferences.localProcessing
    subtitleLang = preferences.subtitleLanguage
    youtubeVideoCodec = preferences.youtubeVideoCodec
    youtubeVideoContainer = preferences.youtubeVideoContainer
    youtubeDubLang = preferences.youtubeDubLanguage
    convertGif = preferences.convertGif
    allowH265 = preferences.allowH265
    tiktokFullAudio = preferences.tiktokFullAudio
    youtubeBetterAudio = preferences.youtubeBetterAudio
  }
}

public enum SourceURLValidator {
  public static func validate(_ input: String) throws -> URL {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw SourceURLValidationError.empty }
    guard trimmed.utf8.count <= 8_192 else { throw SourceURLValidationError.tooLong }
    guard let components = URLComponents(string: trimmed),
      let scheme = components.scheme?.lowercased(),
      ["http", "https"].contains(scheme),
      let host = components.host,
      !host.isEmpty,
      let url = components.url
    else {
      throw SourceURLValidationError.invalid
    }
    return url
  }
}

public enum SourceURLValidationError: LocalizedError, Equatable, Sendable {
  case empty
  case invalid
  case tooLong

  public var errorDescription: String? {
    switch self {
    case .empty: "Paste a public media link first."
    case .invalid: "Enter a complete HTTP or HTTPS link."
    case .tooLong: "This link is too long to process safely."
    }
  }
}
