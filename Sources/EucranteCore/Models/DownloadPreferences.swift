import Foundation

public struct DownloadPreferences: Codable, Equatable, Sendable {
  public var downloadMode: DownloadMode
  public var videoQuality: VideoQuality
  public var audioFormat: AudioFormat
  public var audioBitrate: AudioBitrate
  public var filenameStyle: FilenameStyle
  public var localProcessing: LocalProcessingPreference
  public var disableMetadata: Bool
  public var alwaysProxy: Bool
  public var subtitleLanguage: String?
  public var youtubeVideoCodec: YouTubeVideoCodec
  public var youtubeVideoContainer: YouTubeVideoContainer
  public var youtubeDubLanguage: String?
  public var youtubeBetterAudio: Bool
  public var allowH265: Bool
  public var tiktokFullAudio: Bool
  public var convertGif: Bool

  public init(
    downloadMode: DownloadMode = .automatic,
    videoQuality: VideoQuality = .p1080,
    audioFormat: AudioFormat = .mp3,
    audioBitrate: AudioBitrate = .kbps128,
    filenameStyle: FilenameStyle = .basic,
    localProcessing: LocalProcessingPreference = .disabled,
    disableMetadata: Bool = false,
    alwaysProxy: Bool = false,
    subtitleLanguage: String? = nil,
    youtubeVideoCodec: YouTubeVideoCodec = .h264,
    youtubeVideoContainer: YouTubeVideoContainer = .automatic,
    youtubeDubLanguage: String? = nil,
    youtubeBetterAudio: Bool = false,
    allowH265: Bool = false,
    tiktokFullAudio: Bool = false,
    convertGif: Bool = true
  ) {
    self.downloadMode = downloadMode
    self.videoQuality = videoQuality
    self.audioFormat = audioFormat
    self.audioBitrate = audioBitrate
    self.filenameStyle = filenameStyle
    self.localProcessing = localProcessing
    self.disableMetadata = disableMetadata
    self.alwaysProxy = alwaysProxy
    self.subtitleLanguage = subtitleLanguage
    self.youtubeVideoCodec = youtubeVideoCodec
    self.youtubeVideoContainer = youtubeVideoContainer
    self.youtubeDubLanguage = youtubeDubLanguage
    self.youtubeBetterAudio = youtubeBetterAudio
    self.allowH265 = allowH265
    self.tiktokFullAudio = tiktokFullAudio
    self.convertGif = convertGif
  }
}

public enum DownloadMode: String, Codable, CaseIterable, Identifiable, Sendable {
  case automatic = "auto"
  case audio
  case mute

  public var id: Self { self }
}

public enum VideoQuality: String, Codable, CaseIterable, Identifiable, Sendable {
  case maximum = "max"
  case p4320 = "4320"
  case p2160 = "2160"
  case p1440 = "1440"
  case p1080 = "1080"
  case p720 = "720"
  case p480 = "480"
  case p360 = "360"
  case p240 = "240"
  case p144 = "144"

  public var id: Self { self }
  public var displayName: String { self == .maximum ? "Maximum" : "\(rawValue)p" }
}

public enum AudioFormat: String, Codable, CaseIterable, Identifiable, Sendable {
  case best
  case mp3
  case ogg
  case wav
  case opus

  public var id: Self { self }
  public var displayName: String { rawValue.uppercased() }
}

public enum AudioBitrate: String, Codable, CaseIterable, Identifiable, Sendable {
  case kbps320 = "320"
  case kbps256 = "256"
  case kbps128 = "128"
  case kbps96 = "96"
  case kbps64 = "64"
  case kbps8 = "8"

  public var id: Self { self }
  public var displayName: String { "\(rawValue) kbps" }
}

public enum FilenameStyle: String, Codable, CaseIterable, Identifiable, Sendable {
  case classic
  case pretty
  case basic
  case nerdy

  public var id: Self { self }
}

public enum LocalProcessingPreference: String, Codable, CaseIterable, Identifiable, Sendable {
  case disabled
  case preferred
  case forced

  public var id: Self { self }
}

public enum YouTubeVideoCodec: String, Codable, CaseIterable, Identifiable, Sendable {
  case h264
  case av1
  case vp9

  public var id: Self { self }
}

public enum YouTubeVideoContainer: String, Codable, CaseIterable, Identifiable, Sendable {
  case automatic = "auto"
  case mp4
  case webm
  case mkv

  public var id: Self { self }
}
