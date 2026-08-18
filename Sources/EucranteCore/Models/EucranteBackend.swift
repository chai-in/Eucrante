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

public struct EucranteJobEnvelope: Decodable, Equatable, Sendable {
  public let job: EucranteJobManifest
}

public struct EucranteArtifactResult: Decodable, Equatable, Sendable {
  public let slot: String
  public let size: Int64
  public let etag: String
}

public struct EucranteMultipartStart: Decodable, Equatable, Sendable {
  public let uploadId: String
  public let key: String
}

public struct EucranteMultipartPart: Codable, Equatable, Sendable {
  public let partNumber: Int
  public let etag: String

  public init(partNumber: Int, etag: String) {
    self.partNumber = partNumber
    self.etag = etag
  }
}

public struct EucranteMultipartState: Codable, Equatable, Sendable {
  public let uploadID: String
  public let fileSize: Int64
  public let partSize: Int
  public var parts: [EucranteMultipartPart]
  public var bytesCompleted: Int64

  public init(
    uploadID: String,
    fileSize: Int64,
    partSize: Int,
    parts: [EucranteMultipartPart] = [],
    bytesCompleted: Int64 = 0
  ) {
    self.uploadID = uploadID
    self.fileSize = fileSize
    self.partSize = partSize
    self.parts = parts
    self.bytesCompleted = bytesCompleted
  }
}

public struct EucranteDeleteResult: Decodable, Equatable, Sendable {
  public let deleted: Bool
  public let deletedObjects: Int
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
