import EucranteCore
import SwiftUI

struct SettingsView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    TabView {
      general
        .tabItem { Label("General", systemImage: "gear") }
      video
        .tabItem { Label("Video", systemImage: "video") }
      audio
        .tabItem { Label("Audio", systemImage: "waveform") }
      metadata
        .tabItem { Label("Metadata", systemImage: "tag") }
      localMedia
        .tabItem { Label("YouTube", systemImage: "play.rectangle") }
      privacy
        .tabItem { Label("Privacy", systemImage: "hand.raised") }
    }
    .padding(20)
  }

  private var video: some View {
    Form {
      Section("Defaults") {
        Picker("Quality", selection: $model.preferences.videoQuality) {
          ForEach(VideoQuality.allCases) { quality in
            Text(quality.displayName).tag(quality)
          }
        }
        Text(
          "Custom video uses H.264 MP4 for reliable Apple playback. One-click presets choose their own policy."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }

  private var audio: some View {
    Form {
      Section("Apple audio") {
        Text(
          "Custom audio saves the best AAC/M4A track exposed by the provider. Use Music — Efficient for the storage-balanced policy."
        )
        .foregroundStyle(.secondary)
        Text(
          "Music — Best preserves the highest-quality Apple-compatible audio source Eucrante can verify."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }

  private var metadata: some View {
    Form {
      Section("Filenames") {
        Picker("Filename style", selection: $model.preferences.filenameStyle) {
          ForEach(FilenameStyle.allCases) { style in
            Text(style.displayName).tag(style)
          }
        }
        LabeledContent("Preview") {
          VStack(alignment: .trailing, spacing: 3) {
            Text(model.preferences.filenameStyle.sampleFilename)
              .font(.system(.body, design: .monospaced))
              .lineLimit(1)
              .truncationMode(.middle)
            Text(model.preferences.filenameStyle.explanation)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .animation(.easeInOut(duration: 0.15), value: model.preferences.filenameStyle)
        }
      }
    }
    .formStyle(.grouped)
  }

  private var general: some View {
    Form {
      Section("Downloads") {
        LabeledContent("Destination") {
          HStack {
            Text(model.destinationDirectory.path(percentEncoded: false))
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
            Button("Choose…") { model.chooseDestinationDirectory() }
          }
        }
        Stepper(
          "Up to \(model.maximumConcurrentJobs) simultaneous saves",
          value: $model.maximumConcurrentJobs,
          in: 1...4
        )
        Toggle("Notify when saves finish", isOn: $model.completionNotificationsEnabled)
        Button("Use Default Downloads Folder") { model.resetDestinationDirectory() }
      }
    }
    .formStyle(.grouped)
  }

  private var localMedia: some View {
    Form {
      Section("Local media engine") {
        Label(
          model.localToolsMessage,
          systemImage: model.localToolsReady
            ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
        )
        .foregroundStyle(model.localToolsReady ? Color.green : Color.orange)
        HStack {
          Button {
            Task { await model.refreshLocalToolStatus() }
          } label: {
            if model.isCheckingLocalTools {
              ProgressView().controlSize(.small)
            } else {
              Text("Check Tools")
            }
          }
          .disabled(model.isCheckingLocalTools)
          Button("Export Diagnostics…") { model.exportDiagnostics() }
        }
      }

      Section("YouTube Premium") {
        Picker("Use session from", selection: $model.browserSessionSource) {
          ForEach(BrowserSessionSource.allCases) { source in
            Text(source.displayName).tag(source)
          }
        }
        Text(
          model.browserSessionSource == .none
            ? "Public formats are available without signing in. Choose a browser only when you want Eucrante to use your local signed-in YouTube session."
            : "Eucrante reads the selected browser session only on this Mac. It is passed directly to the local downloader and is never copied, uploaded, or saved by Eucrante."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section {
        Text(
          "Everything runs inside Eucrante on this Mac. There is no server, localhost service, Cloudflare Worker, relay computer, or remote job store."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }

  private var privacy: some View {
    Form {
      Section("Data") {
        Label("No analytics or advertising SDKs", systemImage: "checkmark.shield")
        Label("Job history is stored only on this Mac", systemImage: "internaldrive")
        Label(
          "Browser sessions are used only for provider requests", systemImage: "person.badge.key")
        Label(
          "Diagnostics exclude source links and credentials", systemImage: "doc.badge.gearshape")
        Button("Clear Local History", role: .destructive) { model.clearHistory() }
          .disabled(model.historyJobs.isEmpty)
      }
      Section {
        Text(
          "Eucrante can read a browser session only after you select that browser. It does not bypass DRM or access controls."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }

}
