import Foundation

public struct EucranteDiscovery: Decodable, Equatable, Sendable {
  public let product: String
  public let apiVersion: String
  public let capabilities: [String]
  public let cobaltEndpoint: String
  public let jobsEndpoint: String
  public let retention: String
}

public struct EucranteJobManifest: Decodable, Equatable, Sendable {
  public let schemaVersion: Int
  public let id: UUID
  public let state: String
  public let preset: String
  public let sourceHost: String
  public let createdAt: String
  public let updatedAt: String
}

public struct EucranteJobResult: Decodable, Sendable {
  public let job: EucranteJobManifest
  public let result: CobaltResponse
}

public struct CloudflareAccessCredentials: Equatable, Sendable {
  public let clientID: String
  public let clientSecret: String

  public init(clientID: String, clientSecret: String) {
    self.clientID = clientID
    self.clientSecret = clientSecret
  }
}

public enum EucrantePreset: String, Codable, CaseIterable, Identifiable, Sendable {
  case appleMusicBest = "apple-music-best"
  case appleMusicEfficient = "apple-music-efficient"
  case appleVideoBest = "apple-video-best"
  case appleVideoEfficient = "apple-video-efficient"
  case custom

  public var id: Self { self }
}
