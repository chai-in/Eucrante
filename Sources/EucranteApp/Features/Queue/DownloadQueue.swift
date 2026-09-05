import Combine
import EucranteCore
import Foundation

@MainActor
final class DownloadQueue: ObservableObject {
  @Published private(set) var jobs: [PersistentJob] = []
  @Published private(set) var runningCount = 0
  @Published var isPaused = false { didSet { drain() } }
  var maximumConcurrentJobs = 1 { didSet { drain() } }
  var toolsReady = false { didSet { drain() } }
  var youtubeReady = false { didSet { drain() } }
  var onError: ((String) -> Void)?
  var onCompletion: ((PersistentJob) -> Void)?

  private struct Attempt {
    let id: UUID
    let task: Task<Void, Never>
    var lastProgressAt: ContinuousClock.Instant?
  }

  private let store: JobStore
  private let pipeline: DownloadPipeline
  private var attempts: [UUID: Attempt] = [:]
  private var persistenceAvailable = true

  init(store: JobStore, pipeline: DownloadPipeline) {
    self.store = store
    self.pipeline = pipeline
  }

  var activeJobs: [PersistentJob] {
    // The persisted array is newest-first; timestamps can tie after JSON round trips.
    jobs.reversed().filter { $0.state.isActive }
  }
  var historyJobs: [PersistentJob] { jobs.filter { !$0.state.isActive } }

  func load(defaultRequest: SaveRequest) {
    do {
      try pipeline.workspace.recoverTransientFiles()
      var loaded = try store.load()
      for index in loaded.indices {
        if loaded[index].request == nil {
          loaded[index].request = SaveRequest(
            preferences: loaded[index].preset.requestPreferences(from: defaultRequest.preferences),
            destination: defaultRequest.destination,
            destinationBookmark: defaultRequest.destinationBookmark)
        }
        if (loaded[index].state.isActive && loaded[index].state != .queued)
          || loaded[index].state == .awaitingSelection
        {
          loaded[index].state = .failed
          loaded[index].errorCode = "interrupted"
          loaded[index].errorMessage =
            "Eucrante closed before this job finished. Choose Retry to continue."
          loaded[index].updatedAt = .now
          pipeline.workspace.removeStaging(for: loaded[index].id)
          loaded[index].stagingPath = nil
        }
      }
      jobs = loaded
      try store.save(jobs)
    } catch {
      persistenceAvailable = false
      onError?(error.localizedDescription)
    }
  }

  func enqueue(_ job: PersistentJob) throws {
    var next = jobs
    next.insert(job, at: 0)
    try commit(next)
    drain()
  }

  func retry(_ id: UUID) {
    guard let job = jobs.first(where: { $0.id == id }), job.canRetry, attempts[id] == nil else {
      return
    }
    let reset = PersistentJob(
      id: job.id, sourceURL: job.sourceURL, preset: job.preset, request: job.request,
      mediaMetadata: job.mediaMetadata,
      metadataOverrides: job.metadataOverrides, createdAt: job.createdAt)
    var next = jobs.filter { $0.id != id }
    next.insert(reset, at: 0)
    do {
      try commit(next)
      drain()
    } catch { onError?(error.localizedDescription) }
  }

  func cancel(_ id: UUID) {
    guard let job = jobs.first(where: { $0.id == id }), job.state.isActive,
      job.state != .cancelling
    else { return }
    attempts[id]?.task.cancel()
    mutate(id) {
      $0.state = attempts[id] == nil ? .cancelled : .cancelling
      $0.errorMessage = nil
    }
  }

  func cancelYouTubeJobs() async -> Int {
    let affected = activeJobs.filter { SourceURLValidator.isYouTube($0.sourceURL) }
    let tasks = affected.compactMap { attempts[$0.id]?.task }
    for job in affected { cancel(job.id) }
    for task in tasks { await task.value }
    return affected.count
  }

  func remove(_ id: UUID) {
    guard let job = jobs.first(where: { $0.id == id }), !job.state.isActive, attempts[id] == nil
    else { return }
    replaceHistory(jobs.filter { $0.id != id }, removing: [job])
  }

  func clearHistory() {
    replaceHistory(jobs.filter { $0.state.isActive }, removing: historyJobs)
  }

  func updateFile(_ id: UUID, outputPath: String?) {
    mutate(id) { $0.outputPath = outputPath }
  }

  func markImported(_ id: UUID) {
    mutate(id) { $0.importedToMusic = true }
  }

  private func replaceHistory(_ next: [PersistentJob], removing removed: [PersistentJob]) {
    do {
      try commit(next)
      for job in removed {
        pipeline.workspace.removeStaging(for: job.id)
        ArtworkStore.remove(jobID: job.id, rootDirectory: pipeline.workspace.artwork)
      }
    } catch { onError?(error.localizedDescription) }
  }

  private func commit(_ next: [PersistentJob]) throws {
    try store.save(next)
    jobs = next
    persistenceAvailable = true
  }

  private func drain() {
    guard toolsReady, !isPaused, persistenceAvailable else { return }
    while persistenceAvailable, attempts.count < maximumConcurrentJobs,
      let job = jobs.reversed().first(where: {
        $0.state == .queued && attempts[$0.id] == nil
          && (!SourceURLValidator.isYouTube($0.sourceURL) || youtubeReady)
      })
    {
      start(job)
    }
  }

  private func start(_ job: PersistentJob) {
    let attemptID = UUID()
    mutate(job.id) {
      $0.state = .resolving
      $0.stagingPath = pipeline.workspace.staging(for: job.id).path
    }
    guard persistenceAvailable else {
      if let index = jobs.firstIndex(where: { $0.id == job.id }) { jobs[index].state = .queued }
      return
    }
    let task = Task { [self] in
      // One consumer per attempt, with bounded buffering even during fast local conversions.
      let (updates, continuation) = AsyncStream.makeStream(
        of: DownloadUpdate.self, bufferingPolicy: .bufferingNewest(1))
      let observer = Task { [weak self] in
        for await update in updates {
          self?.receive(update, jobID: job.id, attemptID: attemptID)
        }
      }
      defer {
        continuation.finish()
        observer.cancel()
      }
      do {
        try Task.checkCancellation()
        let result = try await pipeline.run(job) { update in
          continuation.yield(update)
        }
        mutate(job.id) {
          $0.state = .completed
          $0.filename = result.media.url.lastPathComponent
          $0.outputPath = result.media.url.path
          $0.mediaMetadata = result.metadata
          $0.mediaDecision = result.decision
          $0.bytesCompleted = result.media.output.fileSize
          $0.bytesExpected = result.media.output.fileSize
          $0.progress = 1
          $0.stagingPath = nil
          $0.errorCode = nil
          $0.errorMessage = nil
        }
        if let completed = jobs.first(where: { $0.id == job.id }) { onCompletion?(completed) }
      } catch {
        let cancelled = Task.isCancelled || error is CancellationError
        mutate(job.id) {
          $0.state = cancelled ? .cancelled : .failed
          $0.errorMessage = cancelled ? "Cancelled" : error.localizedDescription
          $0.stagingPath = nil
          $0.progress = nil
        }
      }
      attempts[job.id] = nil
      runningCount = attempts.count
      drain()
    }
    attempts[job.id] = Attempt(id: attemptID, task: task)
    runningCount = attempts.count
  }

  private func receive(_ update: DownloadUpdate, jobID: UUID, attemptID: UUID) {
    guard attempts[jobID]?.id == attemptID,
      let job = jobs.first(where: { $0.id == jobID }), job.state.isActive,
      job.state != .cancelling
    else { return }
    let phases: [PersistentJob.State] = [.resolving, .downloading, .processing, .verifying]
    guard let current = phases.firstIndex(of: job.state),
      let incoming = phases.firstIndex(of: update.state),
      incoming >= current
    else { return }
    let now = ContinuousClock.now
    if job.state == update.state, update.progress != 1,
      let previous = attempts[jobID]?.lastProgressAt,
      previous.duration(to: now) < .milliseconds(250)
    {
      return
    }
    attempts[jobID]?.lastProgressAt = now
    mutate(jobID, persist: job.state != update.state) {
      $0.state = update.state
      $0.progress = update.progress.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil }
      if update.state == .downloading {
        $0.bytesCompleted = update.bytesCompleted.map { max(0, $0) }
        $0.bytesExpected = update.bytesExpected.flatMap { $0 > 0 ? $0 : nil }
      }
    }
  }

  private func mutate(_ id: UUID, persist: Bool = true, _ change: (inout PersistentJob) -> Void) {
    guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
    var changed = jobs[index]
    change(&changed)
    guard changed != jobs[index] else { return }
    changed.updatedAt = .now
    jobs[index] = changed
    guard persist else { return }
    do {
      try store.save(jobs)
      persistenceAvailable = true
    } catch {
      persistenceAvailable = false
      onError?(error.localizedDescription)
    }
  }
}
