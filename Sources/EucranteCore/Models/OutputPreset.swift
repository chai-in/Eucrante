import Foundation

public enum EucrantePreset: String, Codable, CaseIterable, Identifiable, Sendable {
  case appleMusicBest = "apple-music-best"
  case appleMusicEfficient = "apple-music-efficient"
  case appleVideoBest = "apple-video-best"
  case appleVideoEfficient = "apple-video-efficient"
  case custom

  public var id: Self { self }
}

extension EucrantePreset {
  public var displayName: String {
    switch self {
    case .appleMusicBest: "Music — Best"
    case .appleMusicEfficient: "Music — Efficient"
    case .appleVideoBest: "Video — Best"
    case .appleVideoEfficient: "Video — Efficient"
    case .custom: "Custom"
    }
  }

  public var shortDetail: String {
    switch self {
    case .appleMusicBest: "Best Apple-compatible audio"
    case .appleMusicEfficient: "Best available AAC · smaller"
    case .appleVideoBest: "Preserve or HEVC"
    case .appleVideoEfficient: "Smaller HEVC"
    case .custom: "Your current settings"
    }
  }

  public var isAudio: Bool {
    self == .appleMusicBest || self == .appleMusicEfficient
  }

  public var requiresLocalVerification: Bool { self != .custom }

  public func requestPreferences(from custom: DownloadPreferences) -> DownloadPreferences {
    guard self != .custom else { return custom }
    var value = custom
    value.videoQuality = .maximum
    value.audioFormat = .best
    value.disableMetadata = false
    value.localProcessing = .preferred

    switch self {
    case .appleMusicBest, .appleMusicEfficient:
      value.downloadMode = .audio
      value.audioBitrate = self == .appleMusicEfficient ? .kbps256 : .kbps320
    case .appleVideoBest, .appleVideoEfficient:
      value.downloadMode = .automatic
      value.youtubeVideoCodec = .h264
      value.youtubeVideoContainer = .mp4
      value.audioBitrate = self == .appleVideoEfficient ? .kbps256 : .kbps320
    case .custom:
      break
    }
    return value
  }
}

public enum MediaDecision: String, Codable, CaseIterable, Sendable {
  case passthrough
  case remux
  case transcodeAAC
  case transcodeALAC
  case transcodeHEVC

  public var displayName: String {
    switch self {
    case .passthrough: "Preserved original"
    case .remux: "Remuxed without quality loss"
    case .transcodeAAC: "Converted to AAC"
    case .transcodeALAC: "Converted to Apple Lossless"
    case .transcodeHEVC: "Converted to HEVC"
    }
  }
}
