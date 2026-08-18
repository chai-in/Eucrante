import Foundation

public enum CobaltResponse: Decodable, Sendable {
  case tunnel(TransferResponse)
  case redirect(TransferResponse)
  case picker(PickerResponse)
  case localProcessing(LocalProcessingResponse)
  case failure(CobaltAPIError)

  private enum CodingKeys: String, CodingKey {
    case status
    case error
  }

  private enum Status: String, Decodable {
    case tunnel
    case redirect
    case picker
    case localProcessing = "local-processing"
    case error
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let status = try container.decode(Status.self, forKey: .status)
    let value = try decoder.singleValueContainer()

    switch status {
    case .tunnel:
      self = .tunnel(try value.decode(TransferResponse.self))
    case .redirect:
      self = .redirect(try value.decode(TransferResponse.self))
    case .picker:
      self = .picker(try value.decode(PickerResponse.self))
    case .localProcessing:
      self = .localProcessing(try value.decode(LocalProcessingResponse.self))
    case .error:
      self = .failure(try container.decode(CobaltAPIError.self, forKey: .error))
    }
  }
}

public struct TransferResponse: Decodable, Equatable, Sendable {
  public let url: URL
  public let filename: String?
}

public struct PickerResponse: Decodable, Equatable, Sendable {
  public let audio: URL?
  public let audioFilename: String?
  public let picker: [PickerItem]
}

public struct PickerItem: Decodable, Equatable, Identifiable, Sendable {
  public enum MediaType: String, Decodable, Sendable {
    case photo
    case video
    case gif
  }

  public let type: MediaType
  public let url: URL
  public let thumb: URL?

  public var id: URL { url }
}

public struct LocalProcessingResponse: Decodable, Equatable, Sendable {
  public let type: String
  public let service: String
  public let tunnel: [URL]
  public let output: LocalProcessingOutput
  public let audio: LocalProcessingAudio?
  public let isHLS: Bool?
}

public struct LocalProcessingOutput: Decodable, Equatable, Sendable {
  public let type: String
  public let filename: String
  public let metadata: [String: String]?
  public let subtitles: Bool?
}

public struct LocalProcessingAudio: Decodable, Equatable, Sendable {
  public let copy: Bool
  public let format: String
  public let bitrate: String
  public let cover: Bool?
  public let cropCover: Bool?
}

public struct CobaltAPIError: Decodable, Error, Equatable, Sendable {
  public let code: String
  public let context: CobaltAPIErrorContext?
}

public struct CobaltAPIErrorContext: Decodable, Equatable, Sendable {
  public let service: String?
  public let limit: Double?
}

public struct CobaltInstanceInfo: Decodable, Equatable, Sendable {
  public let cobalt: CobaltServerInfo
  public let git: CobaltGitInfo?
}

public struct CobaltServerInfo: Decodable, Equatable, Sendable {
  public let version: String
  public let url: URL
  public let startTime: String
  public let turnstileSitekey: String?
  public let services: [String]
}

public struct CobaltGitInfo: Decodable, Equatable, Sendable {
  public let commit: String
  public let branch: String
  public let remote: String
}
