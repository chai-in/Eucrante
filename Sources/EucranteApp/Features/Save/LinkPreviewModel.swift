import Combine
import EucranteCore
import Foundation

@MainActor
final class LinkPreviewModel: ObservableObject {
  @Published private(set) var media: MediaPreview?
  @Published private(set) var isLoading = false
  @Published private(set) var message: String?

  private let previewer: (any LocalMediaPreviewing)?
  private let session: any YouTubeSessionStoring
  private let workspace: DownloadWorkspace
  private let debounce: Duration
  private var tasks: [UUID: Task<Void, Never>] = [:]
  private var requestID = UUID()
  private var scheduledSource: URL?

  init(
    previewer: (any LocalMediaPreviewing)?, session: any YouTubeSessionStoring,
    workspace: DownloadWorkspace, debounce: Duration
  ) {
    self.previewer = previewer
    self.session = session
    self.workspace = workspace
    self.debounce = debounce
  }

  func schedule(_ input: String, toolsReady: Bool, youtubeReady: Bool) {
    let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let source = try? SourceURLValidator.validate(input)
    if let source, source == scheduledSource, message == nil, toolsReady,
      !SourceURLValidator.isYouTube(source) || youtubeReady
    {
      return
    }
    invalidate()
    guard !input.isEmpty else { return }
    guard let source else {
      message = "Enter a complete HTTP or HTTPS media link."
      return
    }
    guard let previewer, toolsReady else { return }
    guard !SourceURLValidator.isYouTube(source) || youtubeReady else {
      message = "Sign in to YouTube in Eucrante to load format details."
      return
    }
    scheduledSource = source
    let id = requestID
    tasks[id] = Task { [weak self] in
      guard let self else { return }
      let directory = workspace.jobs.appendingPathComponent(
        ".preview-\(id.uuidString)", isDirectory: true)
      defer {
        tasks[id] = nil
        try? FileManager.default.removeItem(at: directory)
        if requestID == id { isLoading = false }
      }
      do {
        try await Task.sleep(for: debounce)
        try Task.checkCancellation()
        isLoading = true
        try SecureCredentialFile.prepareDirectory(directory)
        let cookie =
          SourceURLValidator.isYouTube(source)
          ? try await session.exportCookieFile(to: directory) : nil
        try Task.checkCancellation()
        let result = try await previewer.preview(
          sourceURL: source, cookieFile: cookie, workingDirectory: directory)
        try Task.checkCancellation()
        guard requestID == id else { return }
        media = result
        message = nil
      } catch {
        guard requestID == id, !Task.isCancelled else { return }
        message = error.localizedDescription
      }
    }
  }

  func stop() async {
    let pending = Array(tasks.values)
    invalidate()
    for task in pending { await task.value }
  }

  private func invalidate() {
    for task in tasks.values { task.cancel() }
    requestID = UUID()
    scheduledSource = nil
    media = nil
    message = nil
    isLoading = false
  }
}
