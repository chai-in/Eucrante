import EucranteCore
import SwiftUI

struct QueueView: View {
  @ObservedObject var model: AppModel
  @State private var showingClearHistoryConfirmation = false

  var body: some View {
    Group {
      if model.jobs.isEmpty {
        ContentUnavailableView(
          "Nothing in the queue",
          systemImage: "tray",
          description: Text("Active saves and completed files will appear here.")
        )
      } else {
        List {
          if !model.activeJobs.isEmpty {
            Section("In Progress") {
              ForEach(model.activeJobs) { job in
                JobRow(model: model, job: job)
              }
            }
          }

          if !model.historyJobs.isEmpty {
            Section("Recent") {
              ForEach(model.historyJobs) { job in
                JobRow(model: model, job: job)
              }
            }
          }
        }
      }
    }
    .navigationTitle("Queue")
    .toolbar {
      if !model.historyJobs.isEmpty {
        ToolbarItem {
          Button("Clear History", role: .destructive) {
            showingClearHistoryConfirmation = true
          }
        }
      }
    }
    .confirmationDialog(
      "Clear download history?",
      isPresented: $showingClearHistoryConfirmation,
      titleVisibility: .visible
    ) {
      Button("Clear History", role: .destructive) { model.clearHistory() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Downloaded files will stay on this Mac.")
    }
  }
}

private struct JobRow: View {
  @ObservedObject var model: AppModel
  let job: PersistentJob

  var body: some View {
    HStack(spacing: 12) {
      statusIcon
        .frame(width: 24)

      VStack(alignment: .leading, spacing: 5) {
        Text(job.filename ?? job.sourceHost)
          .fontWeight(.medium)
          .lineLimit(1)
          .help(job.filename ?? job.sourceHost)

        HStack(spacing: 8) {
          Text(job.preset.displayName)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .fixedSize()

          Text(detailText)
            .font(.subheadline)
            .foregroundStyle(job.state == .failed ? Color.red : Color.secondary)
            .lineLimit(2)
        }

        if job.state.isActive, let progress = job.progress {
          ProgressView(value: progress)
            .accessibilityLabel(job.state.displayName)
            .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
        }
      }

      Spacer(minLength: 12)
      actions
        .fixedSize()
    }
    .padding(.vertical, 6)
    .contextMenu { menuActions }
  }

  @ViewBuilder
  private var actions: some View {
    if job.state.isActive {
      Button("Cancel", role: .cancel) { model.cancel(job.id) }
    } else if job.state == .failed || job.state == .cancelled {
      Button("Retry") { model.retry(job.id) }
        .buttonStyle(.borderedProminent)
    } else if job.state == .completed, let output = job.outputURL {
      HStack(spacing: 8) {
        if job.preset.isAudio {
          if job.importedToMusic {
            Label("In Music", systemImage: "checkmark")
              .font(.caption)
              .foregroundStyle(.secondary)
          } else {
            Button("Import to Music") { model.importToMusic(job.id) }
              .buttonStyle(.borderedProminent)
          }
        }
        Button("Show in Finder") { model.reveal(output) }
      }
    }
  }

  @ViewBuilder
  private var menuActions: some View {
    if job.state.isActive {
      Button("Cancel", role: .destructive) { model.cancel(job.id) }
    } else {
      if job.state == .failed || job.state == .cancelled {
        Button("Retry") { model.retry(job.id) }
      }
      if let output = job.outputURL {
        Button("Open") { model.open(output) }
        Button("Show in Finder") { model.reveal(output) }
        if job.preset.isAudio, !job.importedToMusic {
          Button("Import to Music") { model.importToMusic(job.id) }
        }
        Divider()
        Button("Move Local File to Trash", role: .destructive) {
          model.removeLocalFile(job.id)
        }
      }
      Divider()
      Button("Remove from History", role: .destructive) {
        model.removeFromHistory(job.id)
      }
    }
  }

  @ViewBuilder
  private var statusIcon: some View {
    switch job.state {
    case .queued, .resolving, .downloading, .processing, .verifying, .uploading:
      ProgressView().controlSize(.small)
    case .awaitingSelection:
      Image(systemName: "square.grid.2x2").foregroundStyle(.blue)
    case .completed:
      Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
    case .failed:
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
    case .cancelled:
      Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
    }
  }

  private var detailText: String {
    if let message = job.errorMessage, job.state == .failed || job.state == .cancelled {
      return message
    }
    if job.state == .completed {
      if let decision = job.mediaDecision {
        return decision.displayName
      }
      if let output = job.outputURL {
        return "Saved to \(output.deletingLastPathComponent().lastPathComponent)"
      }
    }
    if let completed = job.bytesCompleted, completed > 0 {
      let formatter = ByteCountFormatter()
      let current = formatter.string(fromByteCount: completed)
      if let expected = job.bytesExpected, expected > 0 {
        return
          "\(job.state.displayName) · \(current) of \(formatter.string(fromByteCount: expected))"
      }
      return "\(job.state.displayName) · \(current)"
    }
    return job.state.displayName
  }
}
