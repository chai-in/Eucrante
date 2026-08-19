import EucranteCore
import SwiftUI

struct AppShellView: View {
  enum Section: String, CaseIterable, Identifiable {
    case save = "Save"
    case queue = "Queue"

    var id: Self { self }
    var icon: String { self == .save ? "square.and.arrow.down" : "list.bullet.rectangle" }
  }

  @ObservedObject var model: AppModel
  @State private var selection: Section? = .save

  var body: some View {
    NavigationSplitView {
      List(Section.allCases, selection: $selection) { section in
        Label(section.rawValue, systemImage: section.icon)
          .tag(section)
      }
      .navigationTitle("Eucrante")
      .navigationSplitViewColumnWidth(min: 150, ideal: 175, max: 220)
    } detail: {
      switch selection ?? .save {
      case .save:
        SaveView(model: model)
      case .queue:
        QueueView(model: model)
      }
    }
    .tint(.eucranteAccent)
    .toolbar {
      ToolbarItem {
        SettingsLink {
          Label("Settings", systemImage: "gearshape")
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      if let job = model.activeJobs.first {
        activeDownloadBar(job)
      } else if let status = model.statusMessage {
        HStack(spacing: 10) {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
          Text(status)
            .font(.callout)
            .lineLimit(2)
          Spacer()
          Button {
            model.statusMessage = nil
          } label: {
            Image(systemName: "xmark")
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
      }
    }
    .alert(
      "Couldn’t Save",
      isPresented: Binding(
        get: { model.errorMessage != nil },
        set: { if !$0 { model.errorMessage = nil } }
      ),
      actions: {
        Button("OK", role: .cancel) { model.errorMessage = nil }
      },
      message: {
        Text(model.errorMessage ?? "An unknown error occurred.")
      }
    )
  }

  private func activeDownloadBar(_ job: PersistentJob) -> some View {
    VStack(spacing: 0) {
      Divider()
      HStack(spacing: 12) {
        Image(systemName: "arrow.down.circle.fill")
          .font(.title2)
          .foregroundStyle(Color.eucranteAccent)

        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 7) {
            Text(job.preset.displayName)
              .fontWeight(.semibold)
              .lineLimit(1)
            Text("·")
              .foregroundStyle(.tertiary)
            Text(job.state.displayName)
              .foregroundStyle(.secondary)
              .lineLimit(1)
            if model.activeJobs.count > 1 {
              Text("+\(model.activeJobs.count - 1) more")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
            }
            Spacer(minLength: 0)
            if let progress = job.progress {
              Text(progress.formatted(.percent.precision(.fractionLength(0))))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
          }

          if let progress = job.progress {
            ProgressView(value: progress)
              .progressViewStyle(.linear)
              .accessibilityValue(
                progress.formatted(.percent.precision(.fractionLength(0))))
          } else {
            ProgressView()
              .progressViewStyle(.linear)
          }
        }

        Button("Queue") { selection = .queue }
          .buttonStyle(.bordered)
        Button("Cancel", role: .cancel) { model.cancel(job.id) }
          .buttonStyle(.bordered)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 11)
      .background(.bar)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("\(job.preset.displayName), \(job.state.displayName)")
  }
}
