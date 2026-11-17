import EucranteCore
import SwiftUI

struct SettingsView: View {
  @Environment(\.openWindow) private var openWindow
  @ObservedObject var model: AppModel
  @State private var showingClearHistoryConfirmation = false

  var body: some View {
    TabView {
      general
        .tabItem { Label("General", systemImage: "gear") }
      output
        .tabItem { Label("Output", systemImage: "slider.horizontal.3") }
      localMedia
        .tabItem { Label("Websites", systemImage: "play.rectangle") }
      privacy
        .tabItem { Label("Privacy", systemImage: "hand.raised") }
    }
    .padding(20)
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

  private var output: some View {
    Form {
      Section("Custom video") {
        Picker("Default quality", selection: $model.preferences.videoQuality) {
          ForEach(VideoQuality.allCases) { quality in
            Text(quality.displayName).tag(quality)
          }
        }
      }
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
          model.localToolsReady ? "Media tools ready" : model.localToolsMessage,
          systemImage: model.localToolsReady
            ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
        )
        .foregroundStyle(model.localToolsReady ? Color.green : Color.orange)
        .help(model.localToolsMessage)
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
          .frame(minWidth: 100)
          Button("Export Diagnostics…") { model.exportDiagnostics() }
        }
      }

      Section("Website sessions") {
        Text(
          "Public links are checked automatically. If a site requires a login, Eucrante identifies it and offers to reconnect."
        )
        .font(.caption).foregroundStyle(.secondary)
        ForEach(model.knownSites) { site in
          LabeledContent(site.name, value: model.siteStatuses[site]?.label ?? "No saved session")
          HStack {
            Button("Open \(site.name)…") {
              openWindow(id: "main")
              model.openSiteSignIn(site.home)
            }
            if model.siteStatuses[site] != nil {
              Button("Remove Session") { Task { await model.signOut(of: site) } }
            }
          }
        }
        Button("Open Website for Current Link…") {
          openWindow(id: "main")
          model.openSiteSignIn()
        }
        .disabled((try? SourceURLValidator.validate(model.sourceText)) == nil)
        Text(
          "Many supported websites, including Instagram and TikTok, can use their own private session. Availability depends on the site and media; protected streams are not supported."
        )
        .font(.caption).foregroundStyle(.secondary)
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
          "Website sign-ins stay in Eucrante's private browser",
          systemImage: "person.badge.key"
        )
        Label(
          "Diagnostics exclude source links and credentials", systemImage: "doc.badge.gearshape")
        Button("Clear Local History", role: .destructive) {
          showingClearHistoryConfirmation = true
        }
        .disabled(model.historyJobs.isEmpty)
      }
    }
    .formStyle(.grouped)
  }

}
