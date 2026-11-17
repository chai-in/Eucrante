import AppKit
import Combine
import EucranteCore
import Foundation
import UniformTypeIdentifiers
import WebKit

@MainActor
final class AppModel: ObservableObject {
  @Published var sourceText = "" {
    didSet {
      if oldValue != sourceText {
        startTime = ""
        endTime = ""
        trimPreview.reset()
      }
      schedulePreview()
    }
  }
  @Published var musicMetadataDraft = MusicMetadataDraft()
  var mediaPreview: MediaPreview? { preview.media }
  var isLoadingPreview: Bool { preview.isLoading }
  var previewMessage: String? { preview.message }
  @Published var selectedPreset: EucrantePreset = .appleMusicBest
  @Published var startTime = ""
  @Published var endTime = ""
  @Published var coverStyle: CoverStyle = .original
  @Published var removeBlackBars = true
  enum Sheet: String, Identifiable {
    case picker, website
    var id: String { rawValue }
  }
  @Published var presentedSheet: Sheet?
  var showingPagePicker: Bool {
    get { presentedSheet == .picker }
    set {
      if newValue {
        presentedSheet = .picker
      } else if presentedSheet == .picker {
        presentedSheet = nil
      }
    }
  }
  let trimPreview: TrimPreviewModel
  @Published var timelineRevision = 0
  let pagePicker: PagePickerModel
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
  enum SiteStatus: Equatable {
    case saved, checking, verified, needsSignIn, unverified
    var label: String {
      switch self {
      case .saved: "Session saved · checked when used"
      case .unverified: "Access not verified"
      case .checking: "Checking access…"
      case .verified: "Access verified"
      case .needsSignIn: "Sign-in needs attention"
      }
    }
  }
  @Published private(set) var siteStatuses: [MediaSite: SiteStatus] = [:]
  @Published private(set) var signInSource = URL(string: "https://www.youtube.com/")!
  @Published private(set) var recoverySources: [MediaSite: URL] = [:]
  private var accessFailures: [MediaSite: Set<URL>] = [:]
  private var returnToPicker = false
  var currentSite: MediaSite { MediaSite(signInSource) }
  var knownSites: [MediaSite] {
    Set(siteStatuses.keys).union([currentSite]).sorted { $0.host < $1.host }
  }
  var previewNeedsSignIn: Bool { preview.failure == .authenticationRequired }

  var siteWebsiteDataStore: WKWebsiteDataStore? { siteSessionStore.websiteDataStore }
  var showingSiteSignIn: Bool {
    get { presentedSheet == .website }
    set {
      if newValue {
        presentedSheet = .website
      } else if presentedSheet == .website {
        presentedSheet = nil
      }
    }
  }
  @Published private(set) var localToolsReady = false
  @Published private(set) var localToolsMessage = "Checking local media tools…"
  @Published private(set) var isCheckingLocalTools = false

  private let localAcquirer: any LocalMediaAcquiring
  private let siteSessionStore: any SiteSessionStoring
  private let musicImporter = MusicLibraryImporter()
  private let completionNotifier = CompletionNotifier()
  private let defaults: UserDefaults
  let queue: DownloadQueue
  private let preview: LinkPreviewModel
  private let workspace: DownloadWorkspace
  private var subscriptions: Set<AnyCancellable> = []
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
    siteSessionStore: any SiteSessionStoring = SiteSessionStore(),
    jobStore: JobStore = JobStore(),
    previewDebounce: Duration = .milliseconds(450)
  ) {
    self.defaults = defaults
    self.localAcquirer = localAcquirer
    self.siteSessionStore = siteSessionStore
    workspace = DownloadWorkspace(root: jobStore.directoryURL)
    trimPreview = TrimPreviewModel(
      session: siteSessionStore, workspace: workspace,
      resolver: localAcquirer as? LocalMediaAcquirer)
    pagePicker = PagePickerModel(
      previewer: localPreviewer ?? (localAcquirer as? any LocalMediaPreviewing),
      session: siteSessionStore, workspace: workspace)
    preview = LinkPreviewModel(
      previewer: localPreviewer ?? (localAcquirer as? any LocalMediaPreviewing),
      session: siteSessionStore, workspace: workspace, debounce: previewDebounce)
    queue = DownloadQueue(
      store: jobStore,
      pipeline: DownloadPipeline(
        acquirer: localAcquirer, processor: mediaProcessor, transcoder: videoTranscoder,
        session: siteSessionStore, workspace: workspace))
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
    queue.onAccessFailure = { [weak self] source, failure in
      self?.recordAccess(source, failure: failure)
    }
    preview.onResult = { [weak self] source, failure in
      self?.recordAccess(source, failure: failure)
    }
    trimPreview.onAccessFailure = { [weak self] source, failure in
      self?.recordAccess(source, failure: failure)
    }
    pagePicker.onResult = { [weak self] source, failure in
      self?.recordAccess(source, failure: failure)
    }
    queue.onCompletion = { [weak self] in self?.didComplete($0) }
    queue.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(
      in: &subscriptions)
    preview.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(
      in: &subscriptions)
    queue.$runningCount.sink {
      NSApplication.shared.dockTile.badgeLabel = $0 > 0 ? String($0) : nil
    }.store(in: &subscriptions)
    queue.load(defaultRequest: currentRequest(for: .custom))
    for job in queue.jobs where job.canRetry && job.errorCode == "authenticationRequired" {
      recordAccess(job.sourceURL, failure: .authenticationRequired)
    }
    Task { [weak self] in
      guard let self else { return }
      await refreshSiteSession()
      await refreshLocalToolStatus()
    }
  }

  var canSubmit: Bool {
    localToolsReady && (try? SourceURLValidator.validate(sourceText)) != nil
  }

  var isSubmitting: Bool { activeJobCount > 0 }
  var activeJobs: [PersistentJob] { queue.activeJobs }
  var historyJobs: [PersistentJob] { queue.historyJobs }

  private func schedulePreview() {
    preview.schedule(sourceText, toolsReady: localToolsReady)
  }

  private func currentRequest(for preset: EucrantePreset, timeRange: MediaTimeRange? = nil)
    -> SaveRequest
  {
    SaveRequest(
      preferences: preset.requestPreferences(from: preferences), destination: destinationDirectory,
      destinationBookmark: defaults.data(forKey: Self.outputBookmarkKey),
      timeRange: timeRange, expectedDuration: mediaPreview?.duration,
      coverStyle: coverStyle, removeBlackBars: removeBlackBars)
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

    let range: MediaTimeRange?
    do {
      let start = try MediaTimeRange.parse(startTime) ?? 0
      let end = try MediaTimeRange.parse(endTime)
      range = start == 0 && end == nil ? nil : try MediaTimeRange(start: start, end: end)
      if let duration = mediaPreview?.duration { _ = try range?.duration(in: duration) }
    } catch {
      errorMessage = error.localizedDescription
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
            style: coverStyle, removeBlackBars: removeBlackBars,
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
      request: currentRequest(for: selected, timeRange: range),
      mediaMetadata: mediaPreview?.metadata,
      metadataOverrides: metadataOverrides
    )
    do {
      try queue.enqueue(job)
      sourceText = ""
      startTime = ""
      endTime = ""
      coverStyle = .original
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

  func openSiteSignIn(_ source: URL? = nil) {
    signInSource = source ?? (try? SourceURLValidator.validate(sourceText)) ?? currentSite.home
    returnToPicker = showingPagePicker
    showingPagePicker = false
    showingSiteSignIn = true
  }

  private func recordAccess(_ source: URL, failure: LocalAcquisitionError?) {
    let site = MediaSite(source)
    let wasRecovering = accessFailures[site]?.contains(source) == true
    if failure == .authenticationRequired {
      accessFailures[site, default: []].insert(source)
    } else {
      accessFailures[site]?.remove(source)
    }
    if let pending = accessFailures[site]?.sorted(by: { $0.absoluteString < $1.absoluteString })
      .first
    {
      siteStatuses[site] = .needsSignIn
      recoverySources[site] = pending
      queue.blockedSites.insert(site)
      return
    }
    accessFailures[site] = nil
    recoverySources[site] = nil
    queue.blockedSites.remove(site)
    if failure == nil {
      siteStatuses[site] = .verified
    } else if siteStatuses[site] == .checking || wasRecovering {
      siteStatuses[site] = .unverified
      statusMessage = failure?.localizedDescription
    }
  }

  func openPasswordsApp() {
    guard
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Passwords")
    else {
      errorMessage =
        "Open Passwords in System Settings, copy your website login, then paste it here."
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

  func finishSiteSignIn() {
    trimPreview.reset()
    timelineRevision += 1
    showingSiteSignIn = false
    let source = signInSource
    let site = MediaSite(source)
    let restorePicker = returnToPicker
    returnToPicker = false
    Task {
      await preview.stop()
      await pagePicker.invalidateSession(for: site)
      await refreshSiteSession(for: source)
      siteStatuses[site] = .checking
      queue.blockedSites.remove(site)
      // Only retry authentication failures, never unrelated errors or completed jobs.
      let retryIDs = queue.jobs.filter {
        MediaSite($0.sourceURL) == site && $0.canRetry && $0.errorCode == "authenticationRequired"
      }.map(\.id)
      for id in retryIDs { queue.retry(id) }
      let retryingPage = pagePicker.retryFailures(for: site)
      if restorePicker { showingPagePicker = true }
      schedulePreview()
      if retryIDs.isEmpty && !retryingPage && sourceText.isEmpty {
        siteStatuses[site] = await siteSessionStore.hasSavedCookies(for: source) ? .saved : nil
        statusMessage = "Website closed. Access will be checked when you choose a link."
      } else {
        statusMessage = "Rechecking \(site.name) with the updated website session…"
      }
    }
  }

  func refreshSiteSession(for source: URL? = nil) async {
    let source = source ?? signInSource
    let site = MediaSite(source)
    if await siteSessionStore.hasSavedCookies(for: source), siteStatuses[site] == nil {
      siteStatuses[site] = .saved
    }
  }

  func signOut(of site: MediaSite) async {
    trimPreview.reset()
    queue.blockedSites.insert(site)
    await preview.stop()
    await pagePicker.invalidateSession(for: site)
    let cancelled = await queue.cancelJobs(for: site)
    await siteSessionStore.clear(for: site.home)
    siteStatuses[site] = nil
    accessFailures[site] = nil
    recoverySources[site] = nil
    queue.blockedSites.remove(site)
    schedulePreview()
    statusMessage =
      cancelled == 0
      ? "Removed Eucrante's private \(site.name) session."
      : "Signed out and cancelled \(cancelled) \(site.name) saves."
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
      verifiedWebsiteSessions: siteStatuses.values.filter { $0 == .verified }.count,
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

  func selectPageItem(_ row: PagePickerModel.Row) {
    guard let media = row.preview else { return }
    musicMetadataDraft = MusicMetadataDraft()
    startTime = ""
    endTime = ""
    coverStyle = .original
    sourceText = row.item.url.absoluteString
    preview.use(media, source: row.item.url)
    showingPagePicker = false
    focusRequestID = UUID()
    statusMessage = "Review the details, then save when ready."
  }

  func openSafariButtonSetup() {
    do { try SafariPageButton.openSetup() } catch { errorMessage = error.localizedDescription }
  }

  func handleIncomingURL(_ url: URL) {
    if url.scheme == "eucrante", url.host == "page" {
      do {
        let selection = try PageMediaSelection.decode(url)
        pagePicker.load(selection)
        showingPagePicker = true
        NSApplication.shared.activate(ignoringOtherApps: true)
      } catch { errorMessage = "The page button sent invalid or oversized media links." }
      return
    }
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
    recordAccess(job.sourceURL, failure: nil)
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
    let verifiedWebsiteSessions: Int
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
