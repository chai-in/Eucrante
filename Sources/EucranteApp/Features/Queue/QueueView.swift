import EucranteCore
import SwiftUI

enum QueueFilter: String, CaseIterable, Identifiable {
  case all = "All"
  case active = "In Progress"
  case completed = "Saved"
  case attention = "Needs Attention"

  var id: Self { self }

  func includes(_ job: PersistentJob) -> Bool {
    switch self {
    case .all: true
    case .active: job.state.isActive
    case .completed: job.state == .completed
    case .attention: job.canRetry
    }
  }
}

struct QueueView: View {
  @ObservedObject var model: AppModel
  @State private var showingClearHistoryConfirmation = false
  @State private var query = ""
  @State private var filter: QueueFilter = .all

  private var visibleJobs: [PersistentJob] {
    model.jobs.filter {
      filter.includes($0)
        && (query.isEmpty
          || [
            $0.displayTitle, $0.sourceHost, $0.preset.displayName, $0.mediaMetadata?.artist ?? "",
          ]
          .contains { $0.localizedStandardContains(query) })
    }
  }

  var body: some View {
    let visible = visibleJobs
    Group {
      if model.jobs.isEmpty {
        ContentUnavailableView("No saves yet", systemImage: "tray")
      } else if visible.isEmpty {
        ContentUnavailableView.search(text: query)
      } else {
        List {
          let active = visible.reversed().filter { $0.state.isActive }
          let history = visible.filter { !$0.state.isActive }
          if !active.isEmpty {
            Section(model.queuePaused ? "Paused Queue" : "In Progress") {
              ForEach(active) { row($0) }
            }
          }
          if !history.isEmpty {
            Section("Recent") {
              ForEach(history) { row($0) }
            }
          }
        }
        .listStyle(.inset)
      }
    }
    .navigationTitle("Queue")
    .searchable(text: $query, prompt: "Search saves")
    .safeAreaInset(edge: .top, spacing: 0) {
      VStack(spacing: 12) {
        HStack {
          Text("\(model.activeJobs.count) in progress")
          Text("·")
          Text("\(model.historyJobs.filter { $0.state == .completed }.count) saved")
          Spacer()
          Button {
            model.queuePaused.toggle()
          } label: {
            Image(systemName: model.queuePaused ? "play.fill" : "pause.fill")
              .frame(width: 20, height: 20)
          }
          .help(
            model.queuePaused ? "Resume queued saves" : "Pause queued saves; running saves continue"
          )
          .accessibilityLabel(model.queuePaused ? "Resume queue" : "Pause queue")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        Picker("Show", selection: $filter) {
          ForEach(QueueFilter.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }
      .padding(16)
      .background(.bar)
      .overlay(alignment: .bottom) { Divider() }
    }
    .toolbar {
      ToolbarItem {
        Button {
          showingClearHistoryConfirmation = true
        } label: {
          Image(systemName: "trash")
        }
        .disabled(model.historyJobs.isEmpty)
        .help("Clear history")
        .accessibilityLabel("Clear history")
      }
    }
    .confirmationDialog(
      "Clear download history?", isPresented: $showingClearHistoryConfirmation,
      titleVisibility: .visible
    ) {
      Button("Clear History", role: .destructive) { model.clearHistory() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Downloaded files will stay on this Mac.")
    }
  }

  private func row(_ job: PersistentJob) -> some View {
    JobRow(
      model: model, job: job, queuePaused: model.queuePaused,
      youtubeSessionReady: model.youtubeSessionReady,
      isImporting: model.importingJobs.contains(job.id)
    ).equatable()
  }
}

struct JobRow: View, Equatable {
  let model: AppModel
  let job: PersistentJob
  var queuePaused = false
  var youtubeSessionReady = false
  var isImporting = false
  @State private var outputExists: Bool?
  @State private var availabilityRevision = UUID()

  private struct AvailabilityRequest: Equatable {
    let path: String?
    let revision: UUID
  }

  private var outputAvailable: Bool { outputExists == true }

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.model === rhs.model && lhs.job == rhs.job && lhs.queuePaused == rhs.queuePaused
      && lhs.youtubeSessionReady == rhs.youtubeSessionReady && lhs.isImporting == rhs.isImporting
  }

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      statusIcon.frame(width: 26, height: 26)
      VStack(alignment: .leading, spacing: 5) {
        Text(job.displayTitle)
          .fontWeight(.medium)
          .lineLimit(1)
          .help(job.displayTitle)
        Text(job.preset.displayName + " · " + job.sourceHost)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Text(detailText)
          .font(.caption)
          .foregroundStyle(job.state == .failed ? Color.red : .secondary)
          .lineLimit(2)
        if job.state.isActive, let progress = job.progress {
          ProgressView(value: progress)
            .accessibilityLabel(job.state.displayName)
            .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      actions
    }
    .padding(.vertical, 10)
    .accessibilityElement(children: .contain)
    .contextMenu { menuActions }
    .task(id: AvailabilityRequest(path: job.outputPath, revision: availabilityRevision)) {
      await refreshOutputAvailability()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    {
      _ in availabilityRevision = UUID()
    }
  }

  private func refreshOutputAvailability() async {
    guard let path = job.outputPath else {
      outputExists = false
      return
    }
    let available = await Task.detached(priority: .utility) {
      FileManager.default.fileExists(atPath: path)
    }.value
    guard !Task.isCancelled, job.outputPath == path else { return }
    outputExists = available
  }

  @ViewBuilder
  private var actions: some View {
    if job.state.isActive {
      iconButton("Cancel save", icon: "xmark.circle") { model.cancel(job.id) }
        .disabled(job.state == .cancelling)
    } else {
      HStack(spacing: 8) {
        if job.canRetry {
          iconButton("Retry save", icon: "arrow.clockwise") { model.retry(job.id) }
        }
        if let output = job.outputURL, outputAvailable {
          if job.isAudio, !job.importedToMusic {
            iconButton("Import to Music", icon: "music.note.list") { model.importToMusic(job.id) }
              .disabled(isImporting)
          }
          iconButton("Open file", icon: "play.fill") { model.open(output) }
          iconButton("Show in Finder", icon: "folder") { model.reveal(output) }
        }
        Menu {
          menuActions
        } label: {
          Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 24, height: 28)
        .help("More actions")
        .accessibilityLabel("More actions")
      }
    }
  }

  private func iconButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View
  {
    Button(action: action) { Image(systemName: icon).frame(width: 24, height: 28) }
      .buttonStyle(.borderless)
      .help(title)
      .accessibilityLabel(title)
  }

  @ViewBuilder
  private var menuActions: some View {
    if job.state.isActive {
      Button("Cancel", role: .destructive) { model.cancel(job.id) }
        .disabled(job.state == .cancelling)
    } else {
      if job.canRetry { Button("Retry") { model.retry(job.id) } }
      if let output = job.outputURL, outputAvailable {
        Button("Open") { model.open(output) }
        Button("Show in Finder") { model.reveal(output) }
        if job.isAudio, !job.importedToMusic {
          Button("Import to Music") { model.importToMusic(job.id) }
            .disabled(isImporting)
        }
        Divider()
        Button("Move Local File to Trash", role: .destructive) { model.removeLocalFile(job.id) }
      }
      Divider()
      Button("Remove from History", role: .destructive) { model.removeFromHistory(job.id) }
    }
  }

  @ViewBuilder
  private var statusIcon: some View {
    switch job.state {
    case .queued:
      Image(systemName: "clock").foregroundStyle(.secondary)
    case .resolving, .downloading, .processing, .verifying, .uploading, .cancelling:
      ProgressView().controlSize(.small)
    case .awaitingSelection:
      Image(systemName: "square.grid.2x2").foregroundStyle(.blue)
    case .completed:
      Image(systemName: outputAvailable ? "checkmark.circle.fill" : "doc.badge.ellipsis")
        .foregroundStyle(outputAvailable ? Color.green : .secondary)
    case .failed:
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
    case .cancelled:
      Image(systemName: "xmark.circle").foregroundStyle(.secondary)
    }
  }

  private var detailText: String {
    if let message = job.errorMessage, job.canRetry { return message }
    if job.state == .completed {
      guard outputExists != nil else { return "Checking local file…" }
      guard outputAvailable else { return "Local file is no longer available" }
      var parts = [job.mediaDecision?.displayName ?? "Saved"]
      if let bytes = job.bytesCompleted {
        parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
      }
      if job.importedToMusic { parts.append("In Music") }
      return parts.joined(separator: " · ")
    }
    if job.state == .queued {
      if AppModel.isYouTube(job.sourceURL), !youtubeSessionReady {
        return "Waiting for YouTube sign-in"
      }
      if queuePaused { return "Paused" }
    }
    if let progress = job.progress {
      return job.state.displayName + " · "
        + progress.formatted(.percent.precision(.fractionLength(0)))
    }
    return job.state.displayName
  }
}
