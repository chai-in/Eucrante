import Foundation

public struct MediaPreview: Equatable, Sendable {
  public let metadata: MediaMetadata
  public let duration: Double?
  public let formats: [MediaPreviewFormat]

  public init(metadata: MediaMetadata, duration: Double?, formats: [MediaPreviewFormat]) {
    self.metadata = metadata
    self.duration = duration
    self.formats = formats
  }

  public func output(for preset: EucrantePreset) -> PresetOutputPreview? {
    switch preset {
    case .appleMusicBest:
      return audioOutput(maximumBitrate: nil)
    case .appleMusicEfficient:
      return audioOutput(maximumBitrate: 256)
    case .appleVideoBest:
      return videoOutput(efficient: false)
    case .appleVideoEfficient:
      return videoOutput(efficient: true)
    case .custom:
      return nil
    }
  }

  private func audioOutput(maximumBitrate: Double?) -> PresetOutputPreview? {
    let appleAudio = formats.filter {
      $0.hasAudio && !$0.hasVideo
        && ($0.audioCodec?.lowercased().hasPrefix("mp4a") == true
          || $0.container?.lowercased() == "m4a")
    }
    let audioOnly = formats.filter { $0.hasAudio && !$0.hasVideo }
    let available = appleAudio.isEmpty ? audioOnly : appleAudio
    let capped =
      maximumBitrate.map { limit in
        available.filter {
          ($0.audioBitrate ?? $0.totalBitrate ?? .greatestFiniteMagnitude) <= limit
        }
      } ?? available
    guard let selected = (capped.isEmpty ? available : capped).max(by: Self.lowerQuality) else {
      return nil
    }
    let bitrate = selected.audioBitrate ?? selected.totalBitrate
    let size = selected.byteCount(duration: duration)
    return PresetOutputPreview(
      codec: Self.audioCodecName(selected.audioCodec),
      container: "M4A",
      quality: bitrate.flatMap { Int(exactly: $0.rounded()) }.map { "\($0) kbps" },
      estimatedByteCount: size.value,
      sizeIsEstimate: size.estimated
    )
  }

  private func videoOutput(efficient: Bool) -> PresetOutputPreview? {
    let videoOnly = formats.filter { $0.hasVideo && !$0.hasAudio }
    let combined = formats.filter { $0.hasVideo }
    let candidates = videoOnly.isEmpty ? combined : videoOnly
    let wide = candidates.filter {
      let codec = $0.videoCodec?.lowercased() ?? ""
      return codec.hasPrefix("vp9") || codec.hasPrefix("vp09")
    }
    guard let video = (wide.isEmpty ? candidates : wide).max(by: Self.lowerQuality) else {
      return nil
    }
    let audioOnly = formats.filter { $0.hasAudio && !$0.hasVideo }
    let appleAudio = audioOnly.filter {
      $0.audioCodec?.lowercased().hasPrefix("mp4a") == true
        || $0.container?.lowercased() == "m4a"
    }
    let audio = (appleAudio.isEmpty ? audioOnly : appleAudio).max(by: Self.lowerQuality)
    let videoCodec = video.videoCodec?.lowercased() ?? ""
    let requiresHEVC = efficient || videoCodec.hasPrefix("vp9") || videoCodec.hasPrefix("vp09")
    let videoSize = video.byteCount(duration: duration)
    let audioSize: (value: Int64?, estimated: Bool) =
      audio?.byteCount(duration: duration) ?? (nil, true)
    let sum = (videoSize.value ?? 0).addingReportingOverflow(audioSize.value ?? 0)
    let totalSize = sum.overflow ? nil : (sum.partialValue > 0 ? sum.partialValue : nil)
    let resolution = video.height.map { height in
      let fps =
        video.frameRate.flatMap { Int(exactly: $0.rounded()) }
        .flatMap { $0 >= 1 ? " · \($0) fps" : nil } ?? ""
      return "\(height)p\(fps)"
    }
    return PresetOutputPreview(
      codec: requiresHEVC ? "HEVC" : Self.videoCodecName(video.videoCodec),
      container: "MP4",
      quality: resolution,
      estimatedByteCount: totalSize,
      sizeIsEstimate: requiresHEVC || videoSize.estimated || audioSize.estimated
    )
  }

  private static func lowerQuality(_ lhs: MediaPreviewFormat, _ rhs: MediaPreviewFormat) -> Bool {
    let left = (
      lhs.height ?? 0, lhs.width ?? 0, lhs.frameRate ?? 0,
      lhs.totalBitrate ?? lhs.audioBitrate ?? 0
    )
    let right = (
      rhs.height ?? 0, rhs.width ?? 0, rhs.frameRate ?? 0,
      rhs.totalBitrate ?? rhs.audioBitrate ?? 0
    )
    return left < right
  }

  private static func audioCodecName(_ codec: String?) -> String {
    let value = codec?.lowercased() ?? ""
    if value.hasPrefix("mp4a") || value.contains("aac") { return "AAC" }
    if value.contains("opus") { return "Opus → AAC" }
    return codec?.uppercased() ?? "Audio"
  }

  private static func videoCodecName(_ codec: String?) -> String {
    let value = codec?.lowercased() ?? ""
    if value.hasPrefix("avc") || value.contains("h264") { return "H.264" }
    if value.hasPrefix("hev") || value.hasPrefix("hvc") { return "HEVC" }
    if value.hasPrefix("av01") { return "AV1" }
    return codec?.uppercased() ?? "Video"
  }
}

public struct MediaPreviewFormat: Equatable, Sendable {
  public let identifier: String
  public let container: String?
  public let videoCodec: String?
  public let audioCodec: String?
  public let width: Int?
  public let height: Int?
  public let frameRate: Double?
  public let totalBitrate: Double?
  public let audioBitrate: Double?
  public let fileSize: Int64?
  public let approximateFileSize: Int64?

  public init(
    identifier: String,
    container: String?,
    videoCodec: String?,
    audioCodec: String?,
    width: Int?,
    height: Int?,
    frameRate: Double?,
    totalBitrate: Double?,
    audioBitrate: Double?,
    fileSize: Int64?,
    approximateFileSize: Int64?
  ) {
    self.identifier = identifier
    self.container = container
    self.videoCodec = videoCodec
    self.audioCodec = audioCodec
    self.width = width
    self.height = height
    self.frameRate = frameRate
    self.totalBitrate = totalBitrate
    self.audioBitrate = audioBitrate
    self.fileSize = fileSize
    self.approximateFileSize = approximateFileSize
  }

  public var hasVideo: Bool { videoCodec != nil && videoCodec?.lowercased() != "none" }
  public var hasAudio: Bool { audioCodec != nil && audioCodec?.lowercased() != "none" }

  fileprivate func byteCount(duration: Double?) -> (value: Int64?, estimated: Bool) {
    if let fileSize, fileSize > 0 { return (fileSize, false) }
    if let approximateFileSize, approximateFileSize > 0 { return (approximateFileSize, true) }
    guard let duration, duration > 0, let bitrate = totalBitrate ?? audioBitrate, bitrate > 0 else {
      return (nil, true)
    }
    return (Int64(exactly: (duration * bitrate * 1_000 / 8).rounded(.down)), true)
  }
}

public struct PresetOutputPreview: Equatable, Sendable {
  public let codec: String
  public let container: String
  public let quality: String?
  public let estimatedByteCount: Int64?
  public let sizeIsEstimate: Bool

  public init(
    codec: String,
    container: String,
    quality: String?,
    estimatedByteCount: Int64?,
    sizeIsEstimate: Bool
  ) {
    self.codec = codec
    self.container = container
    self.quality = quality
    self.estimatedByteCount = estimatedByteCount
    self.sizeIsEstimate = sizeIsEstimate
  }
}
