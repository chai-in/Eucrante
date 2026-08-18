import AppKit
import Combine
import EucranteCore
import Foundation

@MainActor
final class AppModel: ObservableObject {
  enum JobStatus: Equatable {
    case resolving
    case awaitingSelection
    case downloading
    case completed(URL)
    case failed(String)

    var title: String {
      switch self {
      case .resolving: "Resolving"
      case .awaitingSelection: "Choose items"
      case .downloading: "Downloading"
      case .completed: "Saved"
      case .failed: "Failed"
      }
    }
  }

  struct DownloadJob: Identifiable, Equatable {
    let id: UUID
    let sourceURL: URL
    var filename: String?
    var status: JobStatus
    let createdAt: Date
  }

  struct PickerSelection: Identifiable {
    let id = UUID()
    let jobID: UUID
    let response: PickerResponse
  }

  @Published var sourceText = ""
  @Published var preferences: DownloadPreferences {
    didSet {
      guard let data = try? JSONEncoder().encode(preferences) else { return }
      defaults.set(data, forKey: Self.preferencesKey)
    }
  }
  @Published private(set) var jobs: [DownloadJob] = []
  @Published private(set) var isSubmitting = false
  @Published var errorMessage: String?
  @Published var pickerSelection: PickerSelection?
  @Published var focusRequestID = UUID()

  @Published var endpointText: String
  @Published var accessClientIDText: String
  @Published var accessClientSecretText: String
  @Published private(set) var endpointTestMessage: String?
  @Published private(set) var isTestingEndpoint = false

  private let keychain = KeychainStore()
  private let downloader: any MediaDownloading
  private let defaults: UserDefaults

  private static let endpointKey = "processing.endpoint"
  private static let preferencesKey = "save.preferences.v1"
  private static let accessClientIDAccount = "cloudflare-access-client-id"
  private static let accessClientSecretAccount = "cloudflare-access-client-secret"

  init(
    defaults: UserDefaults = .standard,
    downloader: any MediaDownloading = DownloadService()
  ) {
    self.defaults = defaults
    self.downloader = downloader
    preferences =
      defaults.data(forKey: Self.preferencesKey)
      .flatMap { try? JSONDecoder().decode(DownloadPreferences.self, from: $0) }
      ?? DownloadPreferences()
    endpointText = defaults.string(forKey: Self.endpointKey) ?? ""
    accessClientIDText = (try? keychain.string(for: Self.accessClientIDAccount)) ?? ""
    accessClientSecretText = (try? keychain.string(for: Self.accessClientSecretAccount)) ?? ""
  }

  var canSubmit: Bool {
    !isSubmitting && !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && configuredEndpoint != nil
  }

  var isEndpointConfigured: Bool { configuredEndpoint != nil }

  var destinationDirectory: URL {
    let downloads =
      FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Downloads", isDirectory: true)
    return downloads.appendingPathComponent("Eucrante", isDirectory: true)
  }

  func submit() async {
    guard canSubmit else {
      if configuredEndpoint == nil {
        errorMessage = endpointConfigurationMessage
      }
      return
    }

    let sourceURL: URL
    do {
      sourceURL = try SourceURLValidator.validate(sourceText)
    } catch {
      errorMessage = error.localizedDescription
      return
    }

    guard let client = makeClient() else {
      errorMessage = endpointConfigurationMessage
      return
    }

    let jobID = UUID()
    jobs.insert(
      DownloadJob(id: jobID, sourceURL: sourceURL, status: .resolving, createdAt: .now),
      at: 0
    )
    isSubmitting = true

    do {
      let job = try await client.createJob(
        request: CobaltRequest(sourceURL: sourceURL, preferences: preferences))
      sourceText = ""
      try await handle(job.result, for: jobID)
    } catch {
      fail(jobID, message: userMessage(for: error))
    }

    isSubmitting = false
  }

  func savePickerItem(_ item: PickerItem, for jobID: UUID) async {
    pickerSelection = nil
    update(jobID) { $0.status = .downloading }

    do {
      let saved = try await downloader.download(
        from: item.url,
        suggestedFilename: nil,
        to: destinationDirectory
      )
      update(jobID) {
        $0.filename = saved.url.lastPathComponent
        $0.status = .completed(saved.url)
      }
    } catch {
      fail(jobID, message: userMessage(for: error))
    }
  }

  func saveSettings() {
    let normalizedEndpoint = endpointText.trimmingCharacters(in: .whitespacesAndNewlines)
    endpointText = normalizedEndpoint
    defaults.set(normalizedEndpoint, forKey: Self.endpointKey)

    do {
      if accessClientIDText.isEmpty {
        try keychain.delete(account: Self.accessClientIDAccount)
      } else {
        try keychain.set(accessClientIDText, for: Self.accessClientIDAccount)
      }
      if accessClientSecretText.isEmpty {
        try keychain.delete(account: Self.accessClientSecretAccount)
      } else {
        try keychain.set(accessClientSecretText, for: Self.accessClientSecretAccount)
      }
      endpointTestMessage = "Settings saved."
    } catch {
      endpointTestMessage = error.localizedDescription
    }
  }

  func testEndpoint() async {
    guard let client = makeClient() else {
      endpointTestMessage = endpointConfigurationMessage
      return
    }

    isTestingEndpoint = true
    defer { isTestingEndpoint = false }
    do {
      let info = try await client.discovery()
      endpointTestMessage =
        "Connected to \(info.product) API \(info.apiVersion) · \(info.capabilities.count) capabilities"
    } catch {
      endpointTestMessage = userMessage(for: error)
    }
  }

  func reveal(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  private var configuredEndpoint: URL? {
    let value = endpointText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let endpoint = try? EndpointSecurityPolicy.validate(value) else { return nil }
    guard !hasPartialAccessCredentials else { return nil }
    guard !hasAccessCredentials || EndpointSecurityPolicy.allowsCredentials(to: endpoint) else {
      return nil
    }
    return endpoint
  }

  private var endpointConfigurationMessage: String {
    if hasAccessCredentials,
      let endpoint = try? EndpointSecurityPolicy.validate(endpointText),
      !EndpointSecurityPolicy.allowsCredentials(to: endpoint)
    {
      return
        "Cloudflare Access credentials require HTTPS, except for a loopback endpoint on this Mac."
    }
    if hasPartialAccessCredentials {
      return
        "Enter both Cloudflare Access service-token fields, or leave both empty for local development."
    }
    return "Use the HTTPS URL of your Eucrante deployment."
  }

  private var hasAccessCredentials: Bool {
    !accessClientIDText.isEmpty && !accessClientSecretText.isEmpty
  }

  private var hasPartialAccessCredentials: Bool {
    accessClientIDText.isEmpty != accessClientSecretText.isEmpty
  }

  private func makeClient() -> EucranteAPIClient? {
    guard let endpoint = configuredEndpoint else { return nil }
    let access =
      hasAccessCredentials
      ? CloudflareAccessCredentials(
        clientID: accessClientIDText,
        clientSecret: accessClientSecretText)
      : nil
    return EucranteAPIClient(baseURL: endpoint, access: access)
  }

  private func handle(_ response: CobaltResponse, for jobID: UUID) async throws {
    switch response {
    case .tunnel(let transfer), .redirect(let transfer):
      update(jobID) {
        $0.filename = transfer.filename
        $0.status = .downloading
      }
      let saved = try await downloader.download(
        from: transfer.url,
        suggestedFilename: transfer.filename,
        to: destinationDirectory
      )
      update(jobID) {
        $0.filename = saved.url.lastPathComponent
        $0.status = .completed(saved.url)
      }

    case .picker(let response):
      update(jobID) { $0.status = .awaitingSelection }
      pickerSelection = PickerSelection(jobID: jobID, response: response)

    case .localProcessing(let response):
      fail(
        jobID,
        message:
          "This result requires local \(response.type) processing. Enable it after the Phase 2 media engine is installed."
      )

    case .failure(let error):
      fail(jobID, message: apiErrorMessage(error))
    }
  }

  private func update(_ id: UUID, change: (inout DownloadJob) -> Void) {
    guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
    change(&jobs[index])
  }

  private func fail(_ id: UUID, message: String) {
    update(id) { $0.status = .failed(message) }
    errorMessage = message
  }

  private func apiErrorMessage(_ error: CobaltAPIError) -> String {
    switch error.code {
    case let code where code.contains("auth"):
      "The processing deployment rejected the request. Check Cloudflare Access and container authentication."
    case let code where code.contains("rate"):
      "The processing instance is rate-limiting requests. Wait a moment and try again."
    case let code where code.contains("unsupported"):
      "This link is not supported by the configured processing instance."
    default:
      "The processing instance could not save this link (\(error.code))."
    }
  }

  private func userMessage(for error: Error) -> String {
    if let localized = error as? LocalizedError, let description = localized.errorDescription {
      return description
    }
    return error.localizedDescription
  }
}
