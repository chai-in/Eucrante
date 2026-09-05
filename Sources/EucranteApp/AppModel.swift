import AppKit
import Combine
import EucranteCore
import Foundation
import UniformTypeIdentifiers
import WebKit

@MainActor
final class AppModel: ObservableObject {
  @Published var sourceText = "" {
    didSet { schedulePreview() }
  }
  @Published var musicMetadataDraft = MusicMetadataDraft()
  var mediaPreview: MediaPreview? { preview.media }
  var isLoadingPreview: Bool { preview.isLoading }
  var previewMessage: String? { preview.message }
  @Published var selectedPreset: EucrantePreset = .custom
  @Published var preferences: DownloadPreferences {
    didSet {
      guard let data = try? JSONEncoder().encode(preferences) else { return }
      defaults.set(data, forKey: Self.preferencesKey)
    }
  }
  var jobs: [PersistentJob] { queue.jobs }
  var activeJobCount: Int { queue.runningCount }
  var queuePaused: Bool {
    get { queue.isPaused }
    set {
      queue.isPaused = newValue
      defaults.set(newValue, forKey: "jobs.paused")
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
      queue.maximumConcurrentJobs = clamped
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
  @Published private(set) var youtubeSessionReady = false
  var youtubeWebsiteDataStore: WKWebsiteDataStore? { youtubeSessionStore.websiteDataStore }
  @Published var showingYouTubeSignIn = false
  @Published private(set) var localToolsReady = false
  @Published private(set) var localToolsMessage = "Checking local media tools…"
  @Published private(set) var isCheckingLocalTools = false

  private let localAcquirer: any LocalMediaAcquiring
  private let youtubeSessionStore: any YouTubeSessionStoring
  private let musicImporter = MusicLibraryImporter()
  private let completionNotifier = CompletionNotifier()
  private let defaults: UserDefaults
  let queue: DownloadQueue
  private let preview: LinkPreviewModel
  private let workspace: DownloadWorkspace
  private var subscriptions: Set<AnyCancellable> = []
  private var sessionGeneration = UUID()
  private var signingOut = false
  @Published private(set) var importingJobs: Set<UUID> = []

  private static let preferencesKey = "save.preferences.v1"
  private static let outputBookmarkKey = "downloads.output-bookmark.v1"
  private static let maximumConcurrentKey = "jobs.maximum-concurrent"
  private static let notificationsKey = "notifications.completion-enabled"

  init(
    defaults: UserDefaults = .standard,
    localAcquirer: any LocalMediaAcquiring = LocalMediaAcquirer(),
    localPreviewer: (any LocalMediaPreviewing)? = nil,
    mediaProcessor: LocalMediaProcessor = LocalMediaProcessor(),
    videoTranscoder: AppleVideoTranscoder = AppleVideoTranscoder(),
    youtubeSessionStore: any YouTubeSessionStoring = YouTubeSessionStore(),
    jobStore: JobStore = JobStore(),
    previewDebounce: Duration = .milliseconds(450)
  ) {
    self.defaults = defaults
    self.localAcquirer = localAcquirer
    self.youtubeSessionStore = youtubeSessionStore
    workspace = DownloadWorkspace(root: jobStore.directoryURL)
    preview = LinkPreviewModel(
      previewer: localPreviewer ?? (localAcquirer as? any LocalMediaPreviewing),
      session: youtubeSessionStore, workspace: workspace, debounce: previewDebounce)
    queue = DownloadQueue(
      store: jobStore,
      pipeline: DownloadPipeline(
        acquirer: localAcquirer, processor: mediaProcessor, transcoder: videoTranscoder,
        session: youtubeSessionStore, workspace: workspace))
    preferences =
      defaults.data(forKey: Self.preferencesKey)
      .flatMap { try? JSONDecoder().decode(DownloadPreferences.self, from: $0) }
      ?? DownloadPreferences()
    maximumConcurrentJobs = min(max(1, defaults.integer(forKey: Self.maximumConcurrentKey)), 4)
    completionNotificationsEnabled = defaults.bool(forKey: Self.notificationsKey)
    destinationDirectory = Self.resolveDestination(from: defaults)

    queue.maximumConcurrentJobs = maximumConcurrentJobs
    queue.isPaused = defaults.bool(forKey: "jobs.paused")
    queue.onError = { [weak self] in self?.errorMessage = $0 }
    queue.onCompletion = { [weak self] in self?.didComplete($0) }
    queue.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(
      in: &subscriptions)
    preview.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(
      in: &subscriptions)
    queue.$runningCount.sink {
      NSApplication.shared.dockTile.badgeLabel = $0 > 0 ? String($0) : nil
    }.store(in: &subscriptions)
    queue.load(defaultRequest: currentRequest(for: .custom))
    Task { [weak self] in
      guard let self else { return }
      async let session: Void = refreshYouTubeSession()
      async let tools: Void = refreshLocalToolStatus()
      _ = await (session, tools)
    }
  }

  var canSubmit: Bool {
    localToolsReady && (try? SourceURLValidator.validate(sourceText)) != nil
  }

  var isSubmitting: Bool { activeJobCount > 0 }
  var activeJobs: [PersistentJob] { queue.activeJobs }
  var historyJobs: [PersistentJob] { queue.historyJobs }

  private func schedulePreview() {
    preview.schedule(sourceText, toolsReady: localToolsReady, youtubeReady: youtubeSessionReady)
  }

  private func currentRequest(for preset: EucrantePreset) -> SaveRequest {
    SaveRequest(
      preferences: preset.requestPreferences(from: preferences), destination: destinationDirectory,
      destinationBookmark: defaults.data(forKey: Self.outputBookmarkKey))
  }

  func submit(preset: EucrantePreset? = nil) async {
    guard localToolsReady else {
      errorMessage = "Eucrante's local media tools are not ready. Open Settings and check them."
      return
    }

    let sourceURL: URL
    do {
      sourceURL = try SourceURLValidator.validate(sourceText)
    } catch {
      errorMessage = userMessage(for: error)
      return
    }

    if Self.isYouTube(sourceURL), !youtubeSessionReady {
      showingYouTubeSignIn = true
      statusMessage = "Sign in inside Eucrante to save from YouTube. Your link is still ready."
      return
    }

    let selected = preset ?? selectedPreset
    var metadataOverrides: MediaMetadata?
    let jobID = UUID()
    let isAudio = selected.isAudio || (selected == .custom && preferences.downloadMode == .audio)
    if isAudio {
      do {
        metadataOverrides = try musicMetadataDraft.metadata()
        if let selectedArtwork = metadataOverrides?.artworkURL {
          metadataOverrides?.artworkURL = try ArtworkStore.persist(
            selectedURL: selectedArtwork,
            jobID: jobID,
            rootDirectory: workspace.artwork
          )
        }
      } catch {
        errorMessage = userMessage(for: error)
        return
      }
    }

    let job = PersistentJob(
      id: jobID,
      sourceURL: sourceURL,
      preset: selected,
      request: currentRequest(for: selected),
      mediaMetadata: mediaPreview?.metadata,
      metadataOverrides: metadataOverrides
    )
    do {
      try queue.enqueue(job)
      sourceText = ""
      if isAudio { musicMetadataDraft = MusicMetadataDraft() }
    } catch {
      ArtworkStore.remove(jobID: jobID, rootDirectory: workspace.artwork)
      errorMessage = userMessage(for: error)
    }
  }

  func retry(_ jobID: UUID) { queue.retry(jobID) }
  func cancel(_ jobID: UUID) { queue.cancel(jobID) }
  func removeFromHistory(_ jobID: UUID) { queue.remove(jobID) }

  func removeLocalFile(_ jobID: UUID) {
    guard let job = jobs.first(where: { $0.id == jobID }), let url = job.outputURL else { return }
    do {
      try FileManager.default.trashItem(at: url, resultingItemURL: nil)
      queue.updateFile(jobID, outputPath: nil)
      statusMessage = "Moved the local file to Trash."
    } catch {
      errorMessage = "The local file could not be moved to Trash."
    }
  }

  func importToMusic(_ jobID: UUID) {
    guard let job = jobs.first(where: { $0.id == jobID }), job.isAudio, !job.importedToMusic,
      !importingJobs.contains(jobID),
      let output = job.outputURL
    else { return }
    importingJobs.insert(jobID)
    Task { @MainActor in
      defer { importingJobs.remove(jobID) }
      do {
        try await musicImporter.importFile(at: output, metadata: job.mediaMetadata)
        queue.markImported(jobID)
        statusMessage = "Imported \(output.lastPathComponent) into Music."
      } catch {
        errorMessage = userMessage(for: error)
      }
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

  func chooseMusicArtwork() {
    let panel = NSOpenPanel()
    panel.title = "Choose Music Artwork"
    panel.prompt = "Choose Artwork"
    panel.allowedContentTypes = [.image]
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let selected = panel.url else { return }
    guard ArtworkStore.validateSelection(selected) else {
      errorMessage = ArtworkStoreError.invalidImage.localizedDescription
      return
    }
    musicMetadataDraft.artworkURL = selected
  }

  func clearMusicMetadata() {
    musicMetadataDraft = MusicMetadataDraft()
  }

  func refreshLocalToolStatus() async {
    guard !isCheckingLocalTools else { return }
    isCheckingLocalTools = true
    defer { isCheckingLocalTools = false }
    let status = await localAcquirer.toolStatus()
    localToolsReady = status.ready
    queue.toolsReady = status.ready
    if status.ready {
      let downloader = status.downloaderVersion ?? "ready"
      let runtime =
        status.runtimeVersion?.split(separator: " ").prefix(2).joined(separator: " ")
        ?? "ready"
      let transcoder =
        status.transcoderVersion?.split(separator: " ").prefix(3).joined(separator: " ")
        ?? "converter ready"
      localToolsMessage = "Ready · downloader \(downloader) · \(runtime) · \(transcoder)"
      if !sourceText.isEmpty { schedulePreview() }
    } else {
      localToolsMessage = "Local media tools are missing. Reinstall Eucrante or rebuild the app."
    }
  }

  func openYouTubeSignIn() {
    showingYouTubeSignIn = true
  }

  func openPasswordsApp() {
    guard
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Passwords")
    else {
      errorMessage =
        "Open Passwords in System Settings, copy your Google login, then paste it here."
      return
    }
    let configuration = NSWorkspace.OpenConfiguration()
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) {
      [weak self] _, error in
      guard let error else { return }
      Task { @MainActor [weak self] in
        self?.errorMessage = "Apple Passwords could not be opened: \(error.localizedDescription)"
      }
    }
  }

  func finishYouTubeSignIn() {
    showingYouTubeSignIn = false
    Task {
      // Account switching can change format access even when readiness stays true.
      await preview.stop()
      await refreshYouTubeSession()
      if youtubeSessionReady {
        statusMessage = "YouTube is signed in and ready."
      } else {
        errorMessage = "YouTube sign-in was not completed. Sign in inside Eucrante and try again."
      }
    }
  }

  func refreshYouTubeSession() async {
    let generation = sessionGeneration
    let ready = await youtubeSessionStore.hasAuthenticatedSession()
    guard generation == sessionGeneration, !signingOut else { return }
    youtubeSessionReady = ready
    queue.youtubeReady = ready
    schedulePreview()
  }

  func signOutOfYouTube() async {
    guard !signingOut else { return }
    signingOut = true
    sessionGeneration = UUID()
    youtubeSessionReady = false
    queue.youtubeReady = false
    await preview.stop()
    let cancelled = await queue.cancelYouTubeJobs()
    await youtubeSessionStore.clear()
    signingOut = false
    schedulePreview()
    statusMessage =
      cancelled == 0
      ? "Removed Eucrante's private YouTube session."
      : "Signed out and cancelled \(cancelled) YouTube saves."
  }

  func reveal(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  func open(_ url: URL) {
    NSWorkspace.shared.open(url)
  }

  func clearHistory() { queue.clearHistory() }

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
      authenticatedYouTubeSession: youtubeSessionReady,
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

  private func didComplete(_ job: PersistentJob) {
    guard let filename = job.filename else { return }
    statusMessage = "Saved \(filename)"
    if completionNotificationsEnabled {
      Task { [completionNotifier] in
        await completionNotifier.send(filename: filename, preset: job.preset.displayName)
      }
    }
  }

  private struct DiagnosticsReport: Codable {
    let generatedAt: Date
    let appVersion: String
    let macOSVersion: String
    let localToolsReady: Bool
    let authenticatedYouTubeSession: Bool
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

  nonisolated static func isYouTube(_ url: URL) -> Bool {
    SourceURLValidator.isYouTube(url)
  }
}
