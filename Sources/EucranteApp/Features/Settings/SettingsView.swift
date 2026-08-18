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
      processing
        .tabItem { Label("Processing", systemImage: "server.rack") }
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
        Picker("YouTube codec", selection: $model.preferences.youtubeVideoCodec) {
          Text("H.264 · Most compatible").tag(YouTubeVideoCodec.h264)
          Text("AV1 · Smallest files").tag(YouTubeVideoCodec.av1)
          Text("VP9").tag(YouTubeVideoCodec.vp9)
        }
        Picker("YouTube container", selection: $model.preferences.youtubeVideoContainer) {
          Text("Automatic").tag(YouTubeVideoContainer.automatic)
          Text("MP4").tag(YouTubeVideoContainer.mp4)
          Text("WebM").tag(YouTubeVideoContainer.webm)
          Text("MKV").tag(YouTubeVideoContainer.mkv)
        }
      }

      Section("Service options") {
        Toggle("Allow H.265 from TikTok", isOn: $model.preferences.allowH265)
        Toggle("Convert animated posts to GIF", isOn: $model.preferences.convertGif)
      }
    }
    .formStyle(.grouped)
  }

  private var audio: some View {
    Form {
      Section("Defaults") {
        Picker("Format", selection: $model.preferences.audioFormat) {
          ForEach(AudioFormat.allCases) { format in
            Text(format.displayName).tag(format)
          }
        }
        Picker("Bitrate", selection: $model.preferences.audioBitrate) {
          ForEach(AudioBitrate.allCases) { bitrate in
            Text(bitrate.displayName).tag(bitrate)
          }
        }
      }

      Section("Service options") {
        Toggle("Prefer better YouTube audio", isOn: $model.preferences.youtubeBetterAudio)
        Toggle("Use original TikTok audio", isOn: $model.preferences.tiktokFullAudio)
        TextField("YouTube dub language code", text: youtubeDubLanguage)
          .textFieldStyle(.roundedBorder)
      }
    }
    .formStyle(.grouped)
  }

  private var metadata: some View {
    Form {
      Section("Filenames and tags") {
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
        Toggle("Disable embedded metadata", isOn: $model.preferences.disableMetadata)
      }

      Section("Subtitles") {
        TextField("ISO language code, or leave empty", text: subtitleLanguage)
          .textFieldStyle(.roundedBorder)
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

  private var processing: some View {
    Form {
      Section("Eucrante deployment") {
        TextField("https://eucrante.example.com/", text: $model.endpointText)
          .textFieldStyle(.roundedBorder)
        TextField("Cloudflare Access client ID", text: $model.accessClientIDText)
          .textFieldStyle(.roundedBorder)
        SecureField("Cloudflare Access client secret", text: $model.accessClientSecretText)
          .textFieldStyle(.roundedBorder)

        HStack {
          Button("Save") { model.saveSettings() }
            .buttonStyle(.borderedProminent)
          Button {
            Task { await model.testEndpoint() }
          } label: {
            if model.isTestingEndpoint {
              ProgressView().controlSize(.small)
            } else {
              Text("Test Connection")
            }
          }
          .disabled(model.isTestingEndpoint)
        }

        if let message = model.endpointTestMessage {
          Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }

        Button("Export Diagnostics…") { model.exportDiagnostics() }
      }

      Section("Behavior") {
        Picker("Local processing", selection: $model.preferences.localProcessing) {
          Text("Disabled").tag(LocalProcessingPreference.disabled)
          Text("Preferred").tag(LocalProcessingPreference.preferred)
          Text("Forced").tag(LocalProcessingPreference.forced)
        }
        Toggle("Always proxy downloads", isOn: $model.preferences.alwaysProxy)
      }

      Section {
        Text(
          "Use the Worker URL from a Eucrante stack you control. Access credentials stay in Keychain; the official public Cobalt endpoint is never used."
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
        Label("Cloudflare Access credentials are stored in macOS Keychain", systemImage: "key")
        Label("Job history is stored only on this Mac", systemImage: "internaldrive")
        Label(
          "Diagnostics exclude source links and credentials", systemImage: "doc.badge.gearshape")
        Button("Clear Completed History", role: .destructive) { model.clearHistory() }
          .disabled(model.historyJobs.isEmpty)
      }
      Section {
        Text(
          "The app does not import browser cookies or attempt to access private or DRM-protected media."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }

  private var subtitleLanguage: Binding<String> {
    Binding(
      get: { model.preferences.subtitleLanguage ?? "" },
      set: { model.preferences.subtitleLanguage = $0.isEmpty ? nil : $0.lowercased() }
    )
  }

  private var youtubeDubLanguage: Binding<String> {
    Binding(
      get: { model.preferences.youtubeDubLanguage ?? "" },
      set: { model.preferences.youtubeDubLanguage = $0.isEmpty ? nil : $0.lowercased() }
    )
  }
}
