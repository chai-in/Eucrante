import SwiftUI

struct QueueView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    Group {
      if model.jobs.isEmpty {
        ContentUnavailableView(
          "Nothing in the queue",
          systemImage: "tray",
          description: Text("Saved links and active work will appear here.")
        )
      } else {
        List(model.jobs) { job in
          JobRow(model: model, job: job)
            .padding(.vertical, 6)
        }
      }
    }
    .navigationTitle("Queue")
  }
}

private struct JobRow: View {
  @ObservedObject var model: AppModel
  let job: AppModel.DownloadJob

  var body: some View {
    HStack(spacing: 12) {
      statusIcon
        .frame(width: 24)

      VStack(alignment: .leading, spacing: 3) {
        Text(job.filename ?? job.sourceURL.host() ?? "Media")
          .fontWeight(.medium)
          .lineLimit(1)
        Text(detailText)
          .font(.subheadline)
          .foregroundStyle(isFailure ? Color.red : Color.secondary)
          .lineLimit(2)
      }

      Spacer()

      if case .completed(let url) = job.status {
        Button("Show in Finder") { model.reveal(url) }
      }
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private var statusIcon: some View {
    switch job.status {
    case .resolving, .downloading:
      ProgressView().controlSize(.small)
    case .awaitingSelection:
      Image(systemName: "square.grid.2x2").foregroundStyle(.blue)
    case .completed:
      Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
    case .failed:
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
    }
  }

  private var detailText: String {
    switch job.status {
    case .resolving, .awaitingSelection, .downloading:
      job.status.title
    case .completed(let url):
      "Saved to \(url.deletingLastPathComponent().lastPathComponent)"
    case .failed(let message):
      message
    }
  }

  private var isFailure: Bool {
    if case .failed = job.status { return true }
    return false
  }
}
