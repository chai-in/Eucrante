import AppKit
import Combine
import EucranteCore
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
  struct PickerSelection: Identifiable {
    let id = UUID()
    let jobID: UUID
    let response: PickerResponse
  }

  @Published var sourceText = ""
  @Published var selectedPreset: EucrantePreset = .custom
  @Published var preferences: DownloadPreferences {
    didSet {
      guard let data = try? JSONEncoder().encode(preferences) else { return }
      defaults.set(data, forKey: Self.preferencesKey)
    }
  }
  @Published private(set) var jobs: [PersistentJob] = []
  @Published private(set) var activeJobCount = 0 {
    didSet {
      NSApplication.shared.dockTile.badgeLabel = activeJobCount > 0 ? "\(activeJobCount)" : nil
    }
  }
  @Published var errorMessage: String?
  @Published var statusMessage: String?
  @Published var pickerSelection: PickerSelection?
  @Published var focusRequestID = UUID()
  @Published private(set) var destinationDirectory: URL
  @Published var maximumConcurrentJobs: Int {
    didSet {
      maximumConcurrentJobs = min(max(maximumConcurrentJobs, 1), 4)
      defaults.set(maximumConcurrentJobs, forKey: Self.maximumConcurrentKey)
    }
  }
  @Published var completionNotificationsEnabled: Bool {
    didSet {
      defaults.set(completionNotificationsEnabled, forKey: Self.notificationsKey)
      guard completionNotificationsEnabled, !oldValue else { return }
      Task { [weak self] in
        guard let self else { return }
        let granted = await completionNotifier.requestAuthorization()
        if !granted {
          completionNotificationsEnabled = false
          errorMessage = "Notifications are off. You can allow Eucrante in System Settings."
        }
      }
    }
  }

  @Published var endpointText: String
  @Published var accessClientIDText: String
  @Published var accessClientSecretText: String
  @Published private(set) var endpointTestMessage: String?
  @Published private(set) var isTestingEndpoint = false

  private let keychain = KeychainStore()
  private let downloader: any MediaDownloading
  private let mediaProcessor: LocalMediaProcessor
  private let musicImporter = MusicLibraryImporter()
  private let completionNotifier = CompletionNotifier()
  private let jobStore: JobStore
  private let defaults: UserDefaults
  private var activeTasks: [UUID: Task<Void, Never>] = [:]
  private var persistenceTask: Task<Void, Never>?

  private static let endpointKey = "processing.endpoint"
  private static let preferencesKey = "save.preferences.v1"
  private static let outputBookmarkKey = "downloads.output-bookmark.v1"
  private static let maximumConcurrentKey = "jobs.maximum-concurrent"
  private static let notificationsKey = "notifications.completion-enabled"
  private static let accessClientIDAccount = "cloudflare-access-client-id"
  private static let accessClientSecretAccount = "cloudflare-access-client-secret"

  init(
    defaults: UserDefaults = .standard,
    downloader: any MediaDownloading = DownloadService(),
    mediaProcessor: LocalMediaProcessor = LocalMediaProcessor(),
    jobStore: JobStore = JobStore()
  ) {
    self.defaults = defaults
    self.downloader = downloader
    self.mediaProcessor = mediaProcessor
    self.jobStore = jobStore
    preferences =
      defaults.data(forKey: Self.preferencesKey)
      .flatMap { try? JSONDecoder().decode(DownloadPreferences.self, from: $0) }
      ?? DownloadPreferences()
    endpointText = defaults.string(forKey: Self.endpointKey) ?? ""
    accessClientIDText = (try? keychain.string(for: Self.accessClientIDAccount)) ?? ""
    accessClientSecretText = (try? keychain.string(for: Self.accessClientSecretAccount)) ?? ""
    maximumConcurrentJobs = max(1, defaults.integer(forKey: Self.maximumConcurrentKey))
    completionNotificationsEnabled = defaults.bool(forKey: Self.notificationsKey)
    destinationDirectory = Self.resolveDestination(from: defaults)

    Task { await loadHistory() }
  }

  var canSubmit: Bool {
    !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && configuredEndpoint != nil
      && activeJobCount < maximumConcurrentJobs
  }

  var isSubmitting: Bool { activeJobCount > 0 }
  var isEndpointConfigured: Bool { configuredEndpoint != nil }
  var activeJobs: [PersistentJob] { jobs.filter { $0.state.isActive } }
  var historyJobs: [PersistentJob] { jobs.filter { !$0.state.isActive } }

  func submit(preset: EucrantePreset? = nil) async {
    guard canSubmit else {
      if configuredEndpoint == nil { errorMessage = endpointConfigurationMessage }
      return
    }

    let sourceURL: URL
    do {
      sourceURL = try SourceURLValidator.validate(sourceText)
    } catch {
      errorMessage = userMessage(for: error)
      return
    }

    let selected = preset ?? selectedPreset
    let job = PersistentJob(sourceURL: sourceURL, preset: selected)
    jobs.insert(job, at: 0)
    sourceText = ""
    schedulePersist()
    start(job.id)
  }

  func retry(_ jobID: UUID) {
    guard activeJobCount < maximumConcurrentJobs else {
      errorMessage = "Wait for an active job to finish before retrying this one."
      return
    }
    update(jobID) {
      $0.state = .queued
      $0.errorCode = nil
      $0.errorMessage = nil
      $0.progress = nil
      $0.updatedAt = .now
    }
    start(jobID)
  }

  func cancel(_ jobID: UUID) {
    activeTasks[jobID]?.cancel()
    update(jobID) {
      $0.state = .cancelled
      $0.errorMessage = "Cancelled"
      $0.updatedAt = .now
    }
  }

  func removeFromHistory(_ jobID: UUID) {
    guard let index = jobs.firstIndex(where: { $0.id == jobID }), !jobs[index].state.isActive else {
      return
    }
    jobs.remove(at: index)
    schedulePersist()
  }

  func removeLocalFile(_ jobID: UUID) {
    guard let job = jobs.first(where: { $0.id == jobID }), let url = job.outputURL else { return }
    do {
      try FileManager.default.trashItem(at: url, resultingItemURL: nil)
      update(jobID) {
        $0.outputPath = nil
        $0.updatedAt = .now
      }
      statusMessage = "Moved the local file to Trash. The cloud job was kept."
    } catch {
      errorMessage = "The local file could not be moved to Trash."
    }
  }

  func deleteCloudJob(_ jobID: UUID) async {
    guard let job = jobs.first(where: { $0.id == jobID }), let cloudID = job.cloudID,
      let client = makeClient()
    else { return }
    do {
      let result = try await client.deleteJob(id: cloudID)
      update(jobID) {
        $0.cloudID = nil
        $0.updatedAt = .now
      }
      statusMessage = "Deleted \(result.deletedObjects) retained cloud objects."
    } catch {
      errorMessage = userMessage(for: error)
    }
  }

  func importToMusic(_ jobID: UUID) {
    guard let job = jobs.first(where: { $0.id == jobID }), job.preset.isAudio,
      let output = job.outputURL
    else { return }
    do {
      try musicImporter.importFile(at: output)
      update(jobID) {
        $0.importedToMusic = true
        $0.updatedAt = .now
      }
      statusMessage = "Imported \(output.lastPathComponent) into Music."
    } catch {
      errorMessage = userMessage(for: error)
    }
  }

  func savePickerItem(_ item: PickerItem, for jobID: UUID) async {
    pickerSelection = nil
    guard let job = jobs.first(where: { $0.id == jobID }) else { return }
    do {
      try await downloadAndFinalize(
        transferURL: item.url,
        filename: nil,
        job: job
      )
    } catch {
      fail(jobID, error: error)
    }
  }

  func chooseDestinationDirectory() {
    let panel = NSOpenPanel()
    panel.title = "Choose Eucrante Output Folder"
    panel.prompt = "Choose"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = destinationDirectory
    guard panel.runModal() == .OK, let selected = panel.url else { return }
    do {
      let bookmark = try OutputFolderBookmark.create(for: selected)
      defaults.set(bookmark, forKey: Self.outputBookmarkKey)
      destinationDirectory = selected
      statusMessage = "Downloads will be saved to \(selected.lastPathComponent)."
    } catch {
      errorMessage = userMessage(for: error)
    }
  }

  func resetDestinationDirectory() {
    defaults.removeObject(forKey: Self.outputBookmarkKey)
    destinationDirectory = Self.defaultDestination()
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
      endpointTestMessage = userMessage(for: error)
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

  func open(_ url: URL) {
    NSWorkspace.shared.open(url)
  }

  func clearHistory() {
    jobs.removeAll { !$0.state.isActive }
    schedulePersist()
  }

  func exportDiagnostics() {
    let panel = NSSavePanel()
    panel.title = "Export Eucrante Diagnostics"
    panel.nameFieldStringValue = "Eucrante Diagnostics.json"
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let destination = panel.url else { return }

    let stateCounts = Dictionary(grouping: jobs, by: \PersistentJob.state)
      .mapValues(\.count)
      .reduce(into: [String: Int]()) { result, item in result[item.key.rawValue] = item.value }
    let report = DiagnosticsReport(
      generatedAt: .now,
      appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        ?? "development",
      macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      endpointConfigured: isEndpointConfigured,
      authentication: hasAccessCredentials
        ? "Cloudflare Access service token" : "WARP or deployment policy",
      destinationAvailable: (try? destinationDirectory.checkResourceIsReachable()) ?? false,
      jobStateCounts: stateCounts,
      preferences: preferences
    )
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      try encoder.encode(report).write(to: destination, options: .atomic)
      statusMessage = "Exported privacy-safe diagnostics. No links or credentials were included."
    } catch {
      errorMessage = "Eucrante could not export the diagnostics file."
    }
  }

  func handleIncomingURL(_ url: URL) {
    guard url.scheme?.lowercased() == "eucrante", url.host?.lowercased() == "save",
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let value = components.queryItems?.first(where: { $0.name == "url" })?.value,
      let source = try? SourceURLValidator.validate(value)
    else {
      errorMessage = "That Eucrante link does not contain a valid public media URL."
      return
    }
    sourceText = source.absoluteString
    focusRequestID = UUID()
    statusMessage = "Ready to save the shared link."
  }

  private func start(_ jobID: UUID) {
    guard activeTasks[jobID] == nil else { return }
    activeJobCount += 1
    let task = Task { [weak self] in
      guard let self else { return }
      await execute(jobID)
      activeTasks[jobID] = nil
      activeJobCount = max(0, activeJobCount - 1)
    }
    activeTasks[jobID] = task
  }

  private func execute(_ jobID: UUID) async {
    guard let job = jobs.first(where: { $0.id == jobID }), let client = makeClient() else {
      fail(jobID, message: endpointConfigurationMessage)
      return
    }
    if let output = job.outputURL, job.cloudID != nil, job.mediaDecision != nil,
      FileManager.default.fileExists(atPath: output.path)
    {
      let access = destinationDirectory.startAccessingSecurityScopedResource()
      defer { if access { destinationDirectory.stopAccessingSecurityScopedResource() } }
      do {
        _ = try await mediaProcessor.inspect(output)
        try await retainAndComplete(output, jobID: jobID)
      } catch {
        fail(jobID, error: error)
      }
      return
    }
    update(jobID) {
      $0.state = .resolving
      $0.progress = nil
      $0.updatedAt = .now
    }

    do {
      let jobPreferences = job.preset.requestPreferences(from: preferences)
      let result = try await client.createJob(
        request: CobaltRequest(sourceURL: job.sourceURL, preferences: jobPreferences),
        preset: job.preset
      )
      update(jobID) {
        $0.cloudID = result.job.id
        $0.updatedAt = .now
      }
      guard let refreshed = jobs.first(where: { $0.id == jobID }) else { return }
      try await handle(result.result, for: refreshed)
    } catch is CancellationError {
      update(jobID) {
        $0.state = .cancelled
        $0.errorMessage = "Cancelled"
        $0.updatedAt = .now
      }
    } catch {
      fail(jobID, error: error)
    }
  }

  private func handle(_ response: CobaltResponse, for job: PersistentJob) async throws {
    switch response {
    case .tunnel(let transfer), .redirect(let transfer):
      try await downloadAndFinalize(
        transferURL: transfer.url,
        filename: transfer.filename,
        job: job
      )

    case .picker(let response):
      update(job.id) {
        $0.state = .awaitingSelection
        $0.updatedAt = .now
      }
      pickerSelection = PickerSelection(jobID: job.id, response: response)

    case .localProcessing(let response):
      try await handleLocalProcessing(response, for: job)

    case .failure(let error):
      throw error
    }
  }

  private func handleLocalProcessing(
    _ response: LocalProcessingResponse,
    for job: PersistentJob
  ) async throws {
    let staging = stagingDirectory(for: job.id)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    update(job.id) {
      $0.state = .downloading
      $0.stagingPath = staging.path
      $0.updatedAt = .now
    }

    var inputs: [URL] = []
    for (index, tunnel) in response.tunnel.enumerated() {
      let saved = try await downloader.download(
        from: tunnel,
        suggestedFilename: "input-\(index + 1)",
        to: staging,
        resumeData: nil,
        progress: progressHandler(for: job.id)
      )
      inputs.append(saved.url)
    }
    let prepared = try await mediaProcessor.prepare(
      response,
      inputs: inputs,
      workingDirectory: staging
    )
    try await finalize(prepared, filename: response.output.filename, job: job)
  }

  private func downloadAndFinalize(
    transferURL: URL,
    filename: String?,
    job: PersistentJob
  ) async throws {
    let destination = job.preset == .custom ? destinationDirectory : stagingDirectory(for: job.id)
    update(job.id) {
      $0.state = .downloading
      $0.filename = filename
      $0.stagingPath = job.preset == .custom ? nil : destination.path
      $0.updatedAt = .now
    }

    let access = destinationDirectory.startAccessingSecurityScopedResource()
    defer { if access { destinationDirectory.stopAccessingSecurityScopedResource() } }
    let saved: SavedFile
    do {
      saved = try await downloader.download(
        from: transferURL,
        suggestedFilename: filename,
        to: destination,
        resumeData: job.resumeData,
        progress: progressHandler(for: job.id)
      )
    } catch let error as DownloadError {
      if let data = error.resumeData {
        update(job.id) { $0.resumeData = data }
      }
      throw error
    }
    try await finalize(saved.url, filename: filename ?? saved.url.lastPathComponent, job: job)
  }

  private func finalize(_ input: URL, filename: String, job: PersistentJob) async throws {
    let output: URL
    let decision: MediaDecision
    if job.preset.requiresLocalVerification {
      update(job.id) {
        $0.state = .processing
        $0.progress = 0
        $0.updatedAt = .now
      }
      let processed = try await mediaProcessor.process(
        input,
        preset: job.preset,
        suggestedFilename: filename,
        destination: destinationDirectory,
        progress: processingProgressHandler(for: job.id)
      )
      output = processed.url
      decision = processed.decision
    } else if input.path.hasPrefix(stagingDirectory(for: job.id).path + "/") {
      let processed = try await mediaProcessor.process(
        input,
        preset: .custom,
        suggestedFilename: filename,
        destination: destinationDirectory,
        progress: processingProgressHandler(for: job.id)
      )
      output = processed.url
      decision = processed.decision
    } else {
      output = input
      decision = .passthrough
    }

    update(job.id) {
      $0.state = .verifying
      $0.progress = 1
      $0.updatedAt = .now
    }
    _ = try await mediaProcessor.inspect(output)

    let byteCount =
      (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    update(job.id) {
      $0.filename = output.lastPathComponent
      $0.outputPath = output.path
      $0.bytesCompleted = byteCount
      $0.bytesExpected = byteCount
      $0.mediaDecision = decision
      $0.updatedAt = .now
    }

    try await retainAndComplete(output, jobID: job.id)
  }

  private func retainAndComplete(_ output: URL, jobID: UUID) async throws {
    guard let job = jobs.first(where: { $0.id == jobID }) else { return }

    if let cloudID = job.cloudID,
      let client = makeClient()
    {
      update(jobID) {
        $0.state = .uploading
        $0.progress =
          $0.multipartUpload.map {
            Double($0.bytesCompleted) / Double(max(1, $0.fileSize))
          } ?? 0
        $0.updatedAt = .now
      }
      let slot = "verified-output.\(output.pathExtension.lowercased())"
      _ = try await client.uploadOutput(
        jobID: cloudID,
        fileURL: output,
        slot: slot,
        contentType: contentType(for: output),
        resumeState: job.multipartUpload,
        progress: multipartProgressHandler(for: jobID)
      )
      await Task.yield()
    }

    let byteCount = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    update(jobID) {
      $0.state = .completed
      $0.filename = output.lastPathComponent
      $0.outputPath = output.path
      $0.bytesCompleted = byteCount
      $0.bytesExpected = byteCount
      $0.progress = 1
      $0.resumeData = nil
      $0.multipartUpload = nil
      $0.errorCode = nil
      $0.errorMessage = nil
      $0.updatedAt = .now
    }

    if job.stagingPath != nil {
      try? FileManager.default.removeItem(at: stagingDirectory(for: jobID))
      update(jobID) { $0.stagingPath = nil }
    }
    NSSound(named: "Glass")?.play()
    if completionNotificationsEnabled {
      Task { [completionNotifier] in
        await completionNotifier.send(
          filename: output.lastPathComponent,
          preset: job.preset.displayName
        )
      }
    }
  }

  private func progressHandler(
    for jobID: UUID
  ) -> @Sendable (DownloadProgress) -> Void {
    { [weak self] progress in
      Task { @MainActor [weak self] in
        self?.update(jobID, persist: false) {
          $0.progress = progress.fraction
          $0.bytesCompleted = progress.bytesCompleted
          $0.bytesExpected = progress.bytesExpected
          $0.updatedAt = .now
        }
      }
    }
  }

  private func processingProgressHandler(for jobID: UUID) -> @Sendable (Double) -> Void {
    { [weak self] fraction in
      Task { @MainActor [weak self] in
        self?.update(jobID, persist: false) {
          $0.progress = min(1, max(0, fraction))
          $0.updatedAt = .now
        }
      }
    }
  }

  private func multipartProgressHandler(
    for jobID: UUID
  ) -> @Sendable (EucranteMultipartState?) -> Void {
    { [weak self] state in
      Task { @MainActor [weak self] in
        self?.update(jobID) {
          $0.multipartUpload = state
          if let state {
            $0.progress = Double(state.bytesCompleted) / Double(max(1, state.fileSize))
            $0.bytesCompleted = state.bytesCompleted
            $0.bytesExpected = state.fileSize
          }
          $0.updatedAt = .now
        }
      }
    }
  }

  private func loadHistory() async {
    do {
      var loaded = try await jobStore.load()
      for index in loaded.indices where loaded[index].state.isActive {
        loaded[index].state = .failed
        loaded[index].errorCode = "interrupted"
        loaded[index].errorMessage =
          "Eucrante closed before this job finished. Choose Retry to continue."
        loaded[index].updatedAt = .now
      }
      jobs = loaded.sorted { $0.createdAt > $1.createdAt }
      schedulePersist()
    } catch {
      errorMessage = userMessage(for: error)
    }
  }

  private func schedulePersist() {
    persistenceTask?.cancel()
    let snapshot = jobs
    persistenceTask = Task { [jobStore] in
      try? await Task.sleep(for: .milliseconds(200))
      guard !Task.isCancelled else { return }
      try? await jobStore.save(snapshot)
    }
  }

  private func update(
    _ id: UUID,
    persist: Bool = true,
    change: (inout PersistentJob) -> Void
  ) {
    guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
    change(&jobs[index])
    if persist { schedulePersist() }
  }

  private func fail(_ id: UUID, error: Error) {
    if let cobalt = error as? CobaltAPIError {
      fail(id, message: apiErrorMessage(cobalt), code: cobalt.code)
    } else {
      fail(id, message: userMessage(for: error))
    }
  }

  private func fail(_ id: UUID, message: String, code: String? = nil) {
    update(id) {
      $0.state = .failed
      $0.errorCode = code
      $0.errorMessage = message
      $0.updatedAt = .now
    }
    errorMessage = message
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
        "Enter both Cloudflare Access service-token fields, or leave both empty for WARP authentication."
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

  private func stagingDirectory(for jobID: UUID) -> URL {
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return
      base
      .appendingPathComponent("Eucrante", isDirectory: true)
      .appendingPathComponent("Jobs", isDirectory: true)
      .appendingPathComponent(jobID.uuidString, isDirectory: true)
  }

  private func contentType(for url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "m4a": "audio/mp4"
    case "mp3": "audio/mpeg"
    case "mp4", "m4v": "video/mp4"
    case "mov": "video/quicktime"
    case "jpg", "jpeg": "image/jpeg"
    case "png": "image/png"
    default: "application/octet-stream"
    }
  }

  private func apiErrorMessage(_ error: CobaltAPIError) -> String {
    switch error.code {
    case let code where code.contains("auth"):
      "The processing deployment rejected the request. Check WARP and container authentication."
    case let code where code.contains("rate"):
      "The processing instance is rate-limiting requests. Wait a moment and try again."
    case let code where code.contains("unsupported"):
      "This link is not supported by the configured processing instance."
    default:
      "The processing instance could not save this link (\(error.code))."
    }
  }

  private struct DiagnosticsReport: Codable {
    let generatedAt: Date
    let appVersion: String
    let macOSVersion: String
    let endpointConfigured: Bool
    let authentication: String
    let destinationAvailable: Bool
    let jobStateCounts: [String: Int]
    let preferences: DownloadPreferences
  }

  private func userMessage(for error: Error) -> String {
    if let localized = error as? LocalizedError, let description = localized.errorDescription {
      return description
    }
    return error.localizedDescription
  }

  private static func defaultDestination() -> URL {
    let downloads =
      FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Downloads", isDirectory: true)
    return downloads.appendingPathComponent("Eucrante", isDirectory: true)
  }

  private static func resolveDestination(from defaults: UserDefaults) -> URL {
    guard let data = defaults.data(forKey: outputBookmarkKey),
      let resolved = try? OutputFolderBookmark.resolve(data)
    else {
      return defaultDestination()
    }
    if resolved.stale, let refreshed = try? OutputFolderBookmark.create(for: resolved.url) {
      defaults.set(refreshed, forKey: outputBookmarkKey)
    }
    return resolved.url
  }
}
