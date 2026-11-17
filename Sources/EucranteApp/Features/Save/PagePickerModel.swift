import Combine
import EucranteCore
import Foundation

@MainActor
final class PagePickerModel: ObservableObject {
  struct Row: Identifiable {
    let item: PageMediaSelection.Item
    var preview: MediaPreview?
    var error: String?
    var failure: LocalAcquisitionError?
    var checking = false
    var id: URL { item.url }
  }
  @Published private(set) var rows: [Row] = []
  @Published private(set) var title = "Page items"
  @Published private(set) var truncated = false
  @Published private(set) var running = false
  @Published private(set) var elapsed: Double = 0
  var onResult: ((URL, LocalAcquisitionError?) -> Void)?
  // Bound helper processes, not page size. Results remain in original page order.
  static let workerLimit = 16
  private let previewer: (any LocalMediaPreviewing)?
  private let session: any SiteSessionStoring
  private let workspace: DownloadWorkspace
  private var task: Task<Void, Never>?
  private var generation = UUID()
  private struct Cached {
    let result: Result<MediaPreview, LocalAcquisitionError>
    let expires: ContinuousClock.Instant
  }
  // Only metadata/formats, never signed media URLs or credentials. Never persisted.
  private var cache: [URL: Cached] = [:]

  init(
    previewer: (any LocalMediaPreviewing)?, session: any SiteSessionStoring,
    workspace: DownloadWorkspace
  ) {
    self.previewer = previewer
    self.session = session
    self.workspace = workspace
  }

  func load(_ selection: PageMediaSelection) {
    title = selection.title
    truncated = selection.truncated
    cache = cache.filter { $0.value.expires > .now }
    rows = selection.items.map { item in
      switch cache[item.url]?.result {
      case .success(let preview): Row(item: item, preview: preview)
      case .failure(let failure):
        Row(item: item, error: failure.localizedDescription, failure: failure)
      case nil: Row(item: item)
      }
    }
    start(indices: rows.indices.filter { rows[$0].preview == nil && rows[$0].error == nil })
  }

  @discardableResult
  func retryFailures(for site: MediaSite? = nil) -> Bool {
    let indices = rows.indices.filter {
      rows[$0].preview == nil && (site == nil || MediaSite(rows[$0].item.url) == site)
    }
    guard !indices.isEmpty else { return false }
    for index in indices {
      rows[index].error = nil
      rows[index].failure = nil
      cache[rows[index].item.url] = nil
    }
    // Include unfinished rows from other sites if the earlier scan was interrupted.
    start(indices: rows.indices.filter { rows[$0].preview == nil && rows[$0].error == nil })
    return true
  }

  func invalidateSession(for site: MediaSite) async {
    await stop()
    cache = cache.filter { MediaSite($0.key) != site }
    for index in rows.indices where MediaSite(rows[index].item.url) == site {
      rows[index].preview = nil
      rows[index].error = nil
      rows[index].failure = nil
    }
  }

  private func start(indices: [Int]) {
    let previous = task
    previous?.cancel()
    generation = UUID()
    let id = generation
    running = !indices.isEmpty
    elapsed = 0
    task = Task { [weak self] in
      await previous?.value
      guard let self, !Task.isCancelled, generation == id else { return }
      let started = ContinuousClock.now
      let directory = workspace.jobs.appendingPathComponent(".page-\(id.uuidString)")
      defer {
        try? FileManager.default.removeItem(at: directory)
        if generation == id {
          running = false
          let duration = started.duration(to: .now).components
          elapsed = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        }
      }
      guard !indices.isEmpty else { return }
      do {
        try SecureCredentialFile.prepareDirectory(directory)
        // Read the WebKit cookie store once per site per scan, with an isolated file per worker.
        var cookies: [MediaSite: URL] = [:]
        let sites = Set(indices.map { MediaSite(rows[$0].item.url) })
        for site in sites {
          let siteDirectory = directory.appendingPathComponent(UUID().uuidString)
          if let file = try await session.exportCookieFile(for: site.home, to: siteDirectory) {
            cookies[site] = file
          }
          try Task.checkCancellation()
        }
        await withTaskGroup(of: Void.self) { group in
          for start in 0..<min(Self.workerLimit, indices.count) {
            let assigned = stride(from: start, to: indices.count, by: Self.workerLimit).map {
              indices[$0]
            }
            group.addTask { [self, cookies] in
              await checkRows(assigned, cookies: cookies, directory: directory, generation: id)
            }
          }
        }
      } catch {
        guard generation == id, !Task.isCancelled else { return }
        for index in indices { rows[index].error = error.localizedDescription }
      }
    }
  }

  func stop() async {
    let pending = task
    task?.cancel()
    generation = UUID()
    running = false
    await pending?.value
    for index in rows.indices { rows[index].checking = false }
  }

  private func checkRows(
    _ indices: [Int], cookies: [MediaSite: URL], directory: URL,
    generation id: UUID
  ) async {
    guard !Task.isCancelled, generation == id else { return }
    // Never mix website credentials in a batch; cap its size and lifetime.
    let bySite = Dictionary(grouping: indices) { MediaSite(rows[$0].item.url) }
    for (site, siteIndices) in bySite {
      guard !Task.isCancelled, generation == id else { return }
      let work = directory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: work) }
      do {
        guard let previewer else { throw LocalAcquisitionError.toolsMissing }
        try SecureCredentialFile.prepareDirectory(work)
        let cookie = try cookies[site].map { file in
          try SecureCredentialFile.write(
            Data(contentsOf: file), named: ".site-cookies.txt", to: work)
        }
        for offset in stride(from: 0, to: siteIndices.count, by: 8) {
          let batch = Array(siteIndices[offset..<min(offset + 8, siteIndices.count)])
          guard !Task.isCancelled, generation == id else { return }
          for index in batch { rows[index].checking = true }
          let sources = batch.map { rows[$0].item.url }
          try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [self] in
              try await previewer.previews(
                sourceURLs: sources, cookieFile: cookie, workingDirectory: work
              ) { [self] source, result in
                await accept(source: source, result: result, generation: id)
              }
            }
            group.addTask {
              try await Task.sleep(for: .seconds(40 * batch.count))
              throw LocalAcquisitionError.networkUnavailable
            }
            defer { group.cancelAll() }
            _ = try await group.next()
          }
        }
      } catch {
        guard !Task.isCancelled, generation == id else { return }
        for index in siteIndices where rows[index].preview == nil && rows[index].error == nil {
          accept(
            source: rows[index].item.url,
            result: .failure(error as? LocalAcquisitionError ?? .processFailed(-1)), generation: id)
        }
      }
    }
  }

  private func accept(
    source: URL, result: Result<MediaPreview, LocalAcquisitionError>, generation id: UUID
  ) {
    guard generation == id, let index = rows.firstIndex(where: { $0.item.url == source }) else {
      return
    }
    rows[index].checking = false
    switch result {
    case .success(let preview):
      guard preview.formats.contains(where: { $0.hasAudio || $0.hasVideo }) else {
        accept(source: source, result: .failure(.formatUnavailable), generation: id)
        return
      }
      rows[index].preview = preview
      rows[index].error = nil
      rows[index].failure = nil
      if cache.count >= 256, let key = cache.min(by: { $0.value.expires < $1.value.expires })?.key {
        cache[key] = nil
      }
      cache[source] = Cached(result: .success(preview), expires: .now + .seconds(120))
      onResult?(source, nil)
    case .failure(let failure):
      rows[index].error = failure.localizedDescription
      rows[index].failure = failure
      // Avoid probing a known login failure on every click. Explicit Retry and session
      // changes invalidate this short negative cache immediately.
      if cache.count < 256 {
        cache[source] = Cached(result: .failure(failure), expires: .now + .seconds(30))
      }
      onResult?(source, failure)
    }
  }
}
