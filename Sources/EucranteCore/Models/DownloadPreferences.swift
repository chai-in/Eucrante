import Foundation

public struct DownloadPreferences: Codable, Equatable, Sendable {
  public var downloadMode: DownloadMode
  public var videoQuality: VideoQuality
  public var filenameStyle: FilenameStyle

  public init(
    downloadMode: DownloadMode = .automatic,
    videoQuality: VideoQuality = .p1080,
    filenameStyle: FilenameStyle = .basic
  ) {
    self.downloadMode = downloadMode
    self.videoQuality = videoQuality
    self.filenameStyle = filenameStyle
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

public enum FilenameStyle: String, Codable, CaseIterable, Identifiable, Sendable {
  case classic
  case pretty
  case basic
  case nerdy

  public var id: Self { self }

  public var displayName: String {
    switch self {
    case .classic: "Classic"
    case .pretty: "Pretty"
    case .basic: "Basic"
    case .nerdy: "Nerdy"
    }
  }

  public var sampleFilename: String {
    switch self {
    case .classic: "Midnight Drive - Aurora Vale.mp4"
    case .pretty: "Midnight Drive • Aurora Vale.mp4"
    case .basic: "Midnight Drive.mp4"
    case .nerdy: "Midnight Drive [dQ8k2Lm7].mp4"
    }
  }

  public func filename(
    title: String,
    creator: String?,
    sourceID: String?,
    pathExtension: String
  ) -> String {
    let cleanCreator = creator?.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanID = sourceID?.trimmingCharacters(in: .whitespacesAndNewlines)
    let stem: String
    switch self {
    case .classic:
      stem = cleanCreator.map { $0.isEmpty ? title : "\(title) - \($0)" } ?? title
    case .pretty:
      stem = cleanCreator.map { $0.isEmpty ? title : "\(title) • \($0)" } ?? title
    case .basic:
      stem = title
    case .nerdy:
      stem = cleanID.map { $0.isEmpty ? title : "\(title) [\($0)]" } ?? title
    }
    return FilenameSanitizer.sanitize("\(stem).\(pathExtension)")
  }
}
