import AppKit
import Combine
import EucranteCore
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
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
  @Published var focusRequestID = UUID()
  @Published private(set) var destinationDirectory: URL
  @Published var maximumConcurrentJobs: Int {
    didSet {
      let clamped = min(max(maximumConcurrentJobs, 1), 4)
      if maximumConcurrentJobs != clamped {
        maximumConcurrentJobs = clamped
        return
      }
      defaults.set(maximumConcurrentJobs, forKey: Self.maximumConcurrentKey)
      drainQueue()
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
  @Published var browserSessionSource: BrowserSessionSource {
    didSet { defaults.set(browserSessionSource.rawValue, forKey: Self.browserSessionKey) }
  }
  @Published private(set) var localToolsReady = false
  @Published private(set) var localToolsMessage = "Checking local media tools…"
  @Published private(set) var isCheckingLocalTools = false

  private let localAcquirer: any LocalMediaAcquiring
  private let mediaProcessor: LocalMediaProcessor
  private let musicImporter = MusicLibraryImporter()
  private let completionNotifier = CompletionNotifier()
  private let jobStore: JobStore
  private let defaults: UserDefaults
  private var activeTasks: [UUID: Task<Void, Never>] = [:]
  private var persistenceTask: Task<Void, Never>?

  private static let preferencesKey = "save.preferences.v1"
  private static let outputBookmarkKey = "downloads.output-bookmark.v1"
  private static let maximumConcurrentKey = "jobs.maximum-concurrent"
  private static let notificationsKey = "notifications.completion-enabled"
  private static let browserSessionKey = "youtube.browser-session.v1"

  init(
    defaults: UserDefaults = .standard,
    localAcquirer: any LocalMediaAcquiring = LocalMediaAcquirer(),
    mediaProcessor: LocalMediaProcessor = LocalMediaProcessor(),
    jobStore: JobStore = JobStore()
  ) {
    self.defaults = defaults
    self.localAcquirer = localAcquirer
    self.mediaProcessor = mediaProcessor
    self.jobStore = jobStore
    preferences =
      defaults.data(forKey: Self.preferencesKey)
      .flatMap { try? JSONDecoder().decode(DownloadPreferences.self, from: $0) }
      ?? DownloadPreferences()
    maximumConcurrentJobs = min(max(1, defaults.integer(forKey: Self.maximumConcurrentKey)), 4)
    completionNotificationsEnabled = defaults.bool(forKey: Self.notificationsKey)
    browserSessionSource =
      BrowserSessionSource(
        rawValue: defaults.string(forKey: Self.browserSessionKey) ?? "none") ?? .none
    destinationDirectory = Self.resolveDestination(from: defaults)

    Task {
      await loadHistory()
      await refreshLocalToolStatus()
    }
  }

  var canSubmit: Bool {
    !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && localToolsReady
  }

  var isSubmitting: Bool { activeJobCount > 0 }
  var activeJobs: [PersistentJob] { jobs.filter { $0.state.isActive } }
  var historyJobs: [PersistentJob] { jobs.filter { !$0.state.isActive } }

  func submit(preset: EucrantePreset? = nil) async {
    guard canSubmit else {
      if !localToolsReady {
        errorMessage = "Eucrante's local media tools are not ready. Open Settings and check them."
      }
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
    drainQueue()
  }

  func retry(_ jobID: UUID) {
    update(jobID) {
      $0.state = .queued
      $0.errorCode = nil
      $0.errorMessage = nil
      $0.progress = nil
      $0.updatedAt = .now
    }
    drainQueue()
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
    removeStagingData(for: jobs[index])
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
      statusMessage = "Moved the local file to Trash."
    } catch {
      errorMessage = "The local file could not be moved to Trash."
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

  func refreshLocalToolStatus() async {
    isCheckingLocalTools = true
    defer { isCheckingLocalTools = false }
    let status = await localAcquirer.toolStatus()
    localToolsReady = status.ready
    if status.ready {
      let downloader = status.downloaderVersion ?? "ready"
      let runtime =
        status.runtimeVersion?.split(separator: " ").prefix(2).joined(separator: " ")
        ?? "ready"
      localToolsMessage = "Ready · downloader \(downloader) · \(runtime)"
      drainQueue()
    } else {
      localToolsMessage = "Local media tools are missing. Reinstall Eucrante or rebuild the app."
    }
  }

  func reveal(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  func open(_ url: URL) {
    NSWorkspace.shared.open(url)
  }

  func clearHistory() {
    for job in jobs where !job.state.isActive {
      removeStagingData(for: job)
    }
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
      localToolsReady: localToolsReady,
      browserSession: browserSessionSource.rawValue,
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
    guard activeTasks[jobID] == nil, activeJobCount < maximumConcurrentJobs,
      jobs.first(where: { $0.id == jobID })?.state == .queued
    else { return }
    activeJobCount += 1
    let task = Task { [weak self] in
      guard let self else { return }
      await execute(jobID)
      activeTasks[jobID] = nil
      activeJobCount = max(0, activeJobCount - 1)
      drainQueue()
    }
    activeTasks[jobID] = task
  }

  private func drainQueue() {
    guard localToolsReady else { return }
    while activeJobCount < maximumConcurrentJobs,
      let job = jobs.first(where: { $0.state == .queued && activeTasks[$0.id] == nil })
    {
      start(job.id)
    }
  }

  private func execute(_ jobID: UUID) async {
    guard let job = jobs.first(where: { $0.id == jobID }) else { return }
    let jobDestination = destinationDirectory
    let destinationAccess = jobDestination.startAccessingSecurityScopedResource()
    defer {
      if destinationAccess { jobDestination.stopAccessingSecurityScopedResource() }
    }
    update(jobID) {
      $0.state = .resolving
      $0.progress = nil
      $0.updatedAt = .now
    }

    do {
      let jobPreferences = job.preset.requestPreferences(from: preferences)
      let staging = stagingDirectory(for: job.id)
      update(job.id) {
        $0.state = .downloading
        $0.stagingPath = staging.path
        $0.updatedAt = .now
      }
      let result = try await localAcquirer.acquire(
        sourceURL: job.sourceURL,
        preset: job.preset,
        preferences: jobPreferences,
        browserSession: browserSessionSource,
        workingDirectory: staging,
        progress: localAcquisitionProgressHandler(for: job.id)
      )
      switch result {
      case .single(let input, let filename):
        try await finalize(input, filename: filename, job: job, destination: jobDestination)
      case .merge(let video, let audio, let filename):
        update(job.id) {
          $0.state = .processing
          $0.progress = nil
          $0.updatedAt = .now
        }
        let merged = try await mediaProcessor.merge(
          video: video,
          audio: audio,
          filename: filename,
          workingDirectory: staging
        )
        try await finalize(merged, filename: filename, job: job, destination: jobDestination)
      }
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

  private func finalize(
    _ input: URL,
    filename: String,
    job: PersistentJob,
    destination: URL
  ) async throws {
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
        destination: destination,
        progress: processingProgressHandler(for: job.id)
      )
      output = processed.url
      decision = processed.decision
    } else if input.path.hasPrefix(stagingDirectory(for: job.id).path + "/") {
      let processed = try await mediaProcessor.process(
        input,
        preset: .custom,
        suggestedFilename: filename,
        destination: destination,
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

    let byteCount = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    update(jobID) {
      $0.state = .completed
      $0.filename = output.lastPathComponent
      $0.outputPath = output.path
      $0.bytesCompleted = byteCount
      $0.bytesExpected = byteCount
      $0.progress = 1
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

  private func localAcquisitionProgressHandler(
    for jobID: UUID
  ) -> @Sendable (LocalAcquisitionProgress) -> Void {
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

  private func loadHistory() async {
    do {
      var loaded = try await jobStore.load()
      for index in loaded.indices
      where loaded[index].state.isActive && loaded[index].state != .queued {
        loaded[index].state = .failed
        loaded[index].errorCode = "interrupted"
        loaded[index].errorMessage =
          "Eucrante closed before this job finished. Choose Retry to continue."
        loaded[index].updatedAt = .now
      }
      jobs = loaded.sorted { $0.createdAt > $1.createdAt }
      schedulePersist()
      drainQueue()
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
    fail(id, message: userMessage(for: error))
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

  private func removeStagingData(for job: PersistentJob) {
    guard job.stagingPath != nil else { return }
    let directory = stagingDirectory(for: job.id)
    try? FileManager.default.removeItem(at: directory)
  }

  private struct DiagnosticsReport: Codable {
    let generatedAt: Date
    let appVersion: String
    let macOSVersion: String
    let localToolsReady: Bool
    let browserSession: String
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
