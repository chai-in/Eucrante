import Foundation

public struct PersistentJob: Codable, Equatable, Identifiable, Sendable {
  public enum State: String, Codable, CaseIterable, Sendable {
    case queued
    case resolving
    case awaitingSelection
    case downloading
    case processing
    case verifying
    case uploading
    case cancelling
    case completed
    case failed
    case cancelled

    public var isActive: Bool {
      switch self {
      case .queued, .resolving, .downloading, .processing, .verifying, .uploading, .cancelling: true
      case .awaitingSelection, .completed, .failed, .cancelled: false
      }
    }

    public var displayName: String {
      switch self {
      case .queued: "Queued"
      case .resolving: "Preparing"
      case .awaitingSelection: "Choose an item"
      case .downloading: "Downloading"
      case .processing: "Optimizing for Apple devices"
      case .verifying: "Checking the finished file"
      case .uploading: "Finishing"
      case .cancelling: "Cancelling"
      case .completed: "Completed"
      case .failed: "Failed"
      case .cancelled: "Cancelled"
      }
    }
  }

  public let id: UUID
  public let sourceURL: URL
  public let preset: EucrantePreset
  public var request: SaveRequest?
  public var state: State
  public var progress: Double?
  public var bytesCompleted: Int64?
  public var bytesExpected: Int64?
  public var filename: String?
  public var outputPath: String?
  public var stagingPath: String?
  public var errorCode: String?
  public var errorMessage: String?
  public var mediaDecision: MediaDecision?
  public var mediaMetadata: MediaMetadata?
  public var metadataOverrides: MediaMetadata?
  public var importedToMusic: Bool
  public var createdAt: Date
  public var updatedAt: Date

  public init(
    id: UUID = UUID(),
    sourceURL: URL,
    preset: EucrantePreset,
    request: SaveRequest? = nil,
    state: State = .queued,
    progress: Double? = nil,
    bytesCompleted: Int64? = nil,
    bytesExpected: Int64? = nil,
    filename: String? = nil,
    outputPath: String? = nil,
    stagingPath: String? = nil,
    errorCode: String? = nil,
    errorMessage: String? = nil,
    mediaDecision: MediaDecision? = nil,
    mediaMetadata: MediaMetadata? = nil,
    metadataOverrides: MediaMetadata? = nil,
    importedToMusic: Bool = false,
    createdAt: Date = .now,
    updatedAt: Date = .now
  ) {
    self.id = id
    self.sourceURL = sourceURL
    self.preset = preset
    self.request = request
    self.state = state
    self.progress = progress
    self.bytesCompleted = bytesCompleted
    self.bytesExpected = bytesExpected
    self.filename = filename
    self.outputPath = outputPath
    self.stagingPath = stagingPath
    self.errorCode = errorCode
    self.errorMessage = errorMessage
    self.mediaDecision = mediaDecision
    self.mediaMetadata = mediaMetadata
    self.metadataOverrides = metadataOverrides
    self.importedToMusic = importedToMusic
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public var outputURL: URL? { outputPath.map(URL.init(fileURLWithPath:)) }
  public var sourceHost: String { sourceURL.host() ?? "Unknown source" }
  public var canRetry: Bool { state == .failed || state == .cancelled }
  public var isAudio: Bool {
    preset.isAudio || (preset == .custom && request?.preferences.downloadMode == .audio)
  }
  public var displayTitle: String { filename ?? mediaMetadata?.title ?? sourceHost }
}

public struct SaveRequest: Codable, Equatable, Sendable {
  public let preferences: DownloadPreferences
  public let destination: URL
  public let destinationBookmark: Data?

  public init(preferences: DownloadPreferences, destination: URL, destinationBookmark: Data? = nil)
  {
    self.preferences = preferences
    self.destination = destination
    self.destinationBookmark = destinationBookmark
  }
}

public struct JobLibrarySnapshot: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var jobs: [PersistentJob]

  public init(schemaVersion: Int = JobStore.currentSchemaVersion, jobs: [PersistentJob] = []) {
    self.schemaVersion = schemaVersion
    self.jobs = jobs
  }
}
