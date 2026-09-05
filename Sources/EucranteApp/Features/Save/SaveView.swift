import AppKit
import EucranteCore
import SwiftUI

struct SaveView: View {
  @ObservedObject var model: AppModel
  @FocusState private var sourceFocused: Bool
  @State private var customExpanded = false

  private let presetColumns = [
    GridItem(.flexible(), spacing: 10),
    GridItem(.flexible(), spacing: 10),
  ]

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        VStack(alignment: .leading, spacing: 20) {
          HStack(spacing: 12) {
            Image(systemName: "arrow.down.document")
              .font(.title2)
              .foregroundStyle(Color.eucranteAccent)
            Text("New Save").font(.title2.weight(.semibold))
            Spacer()
            if model.queuePaused {
              Label("Queue paused", systemImage: "pause.circle")
                .font(.caption).foregroundStyle(.secondary)
            }
          }
          sourceField
          mediaPreview

          LazyVGrid(columns: presetColumns, spacing: 10) {
            presetButton(.appleMusicBest, icon: "music.note")
            presetButton(.appleMusicEfficient, icon: "waveform.badge.minus")
            presetButton(.appleVideoBest, icon: "film")
            presetButton(.appleVideoEfficient, icon: "rectangle.compress.vertical")
          }

          MusicMetadataEditor(model: model)

          Divider()

          DisclosureGroup("Custom options", isExpanded: $customExpanded) {
            VStack(spacing: 14) {
              Picker("Mode", selection: $model.preferences.downloadMode) {
                Label("Auto", systemImage: "sparkles").tag(DownloadMode.automatic)
                Label("Audio", systemImage: "waveform").tag(DownloadMode.audio)
                Label("Mute", systemImage: "speaker.slash").tag(DownloadMode.mute)
              }
              .pickerStyle(.segmented)
              .labelsHidden()

              quickOptions

              Button {
                Task { await model.submit(preset: .custom) }
              } label: {
                Label("Save with Custom Settings", systemImage: "slider.horizontal.3")
                  .frame(maxWidth: .infinity, minHeight: 26)
              }
              .buttonStyle(.borderedProminent)
              .controlSize(.large)
              .disabled(!model.canSubmit)
              .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 12)
          }
        }
        .frame(maxWidth: 660)

        HStack(spacing: 8) {
          Image(systemName: "folder")
          Text(model.destinationDirectory.lastPathComponent)
            .lineLimit(1)
            .help(model.destinationDirectory.path(percentEncoded: false))
          Spacer()
          Button("Choose…") { model.chooseDestinationDirectory() }
            .buttonStyle(.link)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: 660, alignment: .leading)
      }
      .padding(.horizontal, 28)
      .padding(.vertical, 24)
      .frame(maxWidth: .infinity)
    }
    .navigationTitle("Save")
    .dropDestination(for: URL.self) { urls, _ in
      guard let url = urls.first,
        let validated = try? SourceURLValidator.validate(url.absoluteString)
      else { return false }
      model.sourceText = validated.absoluteString
      sourceFocused = true
      return true
    }
    .onAppear { sourceFocused = true }
    .onChange(of: model.focusRequestID) { sourceFocused = true }
  }

  private var sourceField: some View {
    HStack(spacing: 10) {
      Image(systemName: "link")
        .foregroundStyle(.secondary)
      TextField("https://…", text: $model.sourceText)
        .textFieldStyle(.plain)
        .font(.body)
        .focused($sourceFocused)
        .onSubmit { Task { await model.submit() } }
        .accessibilityLabel("Public media link")
      if model.sourceText.isEmpty {
        Button {
          if let text = NSPasteboard.general.string(forType: .string) { model.sourceText = text }
        } label: {
          Image(systemName: "document.on.clipboard")
        }
        .buttonStyle(.plain)
        .help("Paste link")
        .accessibilityLabel("Paste link")
      }
      if !model.sourceText.isEmpty {
        Button {
          model.sourceText = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear link")
        .help("Clear link")
      }
    }
    .padding(.horizontal, 14)
    .frame(height: 44)
    .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(
          sourceFocused ? Color.eucranteAccent : Color.secondary.opacity(0.25),
          lineWidth: sourceFocused ? 2 : 1)
    }
  }

  @ViewBuilder
  private var mediaPreview: some View {
    if model.isLoadingPreview {
      HStack(spacing: 10) {
        ProgressView()
          .controlSize(.small)
        Text("Loading preview…")
          .font(.callout)
          .foregroundStyle(.secondary)
        Spacer()
      }
      .transition(.opacity)
    } else if let preview = model.mediaPreview {
      HStack(spacing: 14) {
        AsyncImage(url: preview.metadata.artworkURL) { phase in
          if case .success(let image) = phase {
            image.resizable().scaledToFill()
          } else {
            Image(systemName: "play.rectangle.fill")
              .font(.title2)
              .foregroundStyle(.secondary)
          }
        }
        .frame(width: 76, height: 76)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

        VStack(alignment: .leading, spacing: 4) {
          Text(preview.metadata.title ?? "Untitled media")
            .font(.headline)
            .lineLimit(2)
          if let artist = preview.metadata.artist {
            Text(artist)
              .font(.callout)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          Text(previewSummary(preview))
            .font(.caption)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .transition(.opacity)
    } else if let message = model.previewMessage {
      HStack(spacing: 8) {
        Image(systemName: "info.circle")
        Text(message)
          .fixedSize(horizontal: false, vertical: true)
        if let url = try? SourceURLValidator.validate(model.sourceText),
          AppModel.isYouTube(url), !model.youtubeSessionReady
        {
          Button("Sign In") { model.openYouTubeSignIn() }
        }
        Spacer()
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private func presetButton(_ preset: EucrantePreset, icon: String) -> some View {
    Button {
      Task { await model.submit(preset: preset) }
    } label: {
      HStack(spacing: 10) {
        Image(systemName: icon)
          .font(.title3)
          .frame(width: 24)
        VStack(alignment: .leading, spacing: 2) {
          Text(preset.displayName)
            .fontWeight(.semibold)
          if let detail = presetDetail(preset) {
            Text(detail)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(2)
          }
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 12)
      .frame(
        maxWidth: .infinity,
        minHeight: 72,
        alignment: .leading
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.bordered)
    .disabled(!model.canSubmit)
    .accessibilityHint("Starts the save immediately when a valid link is present")
  }

  private func presetDetail(_ preset: EucrantePreset) -> String? {
    guard let output = model.mediaPreview?.output(for: preset) else {
      switch preset {
      case .appleMusicBest: return "Original audio quality"
      case .appleMusicEfficient: return "AAC audio, smaller files"
      case .appleVideoBest: return "Highest available resolution"
      case .appleVideoEfficient: return "HEVC video, smaller files"
      case .custom: return nil
      }
    }
    var parts = [output.codec, output.container]
    if let quality = output.quality { parts.append(quality) }
    if let bytes = output.estimatedByteCount {
      let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
      parts.append(output.sizeIsEstimate ? "~\(size)" : size)
    }
    return parts.joined(separator: " · ")
  }

  private func previewSummary(_ preview: MediaPreview) -> String {
    var parts: [String] = []
    if let album = preview.metadata.album { parts.append(album) }
    if let year = preview.metadata.year { parts.append(String(year)) }
    if let duration = preview.duration, duration.isFinite, duration > 0 {
      let total = Int(exactly: duration.rounded()) ?? 0
      parts.append(String(format: "%d:%02d", total / 60, total % 60))
    }
    parts.append("\(preview.formats.count) \(preview.formats.count == 1 ? "format" : "formats")")
    return parts.joined(separator: " · ")
  }

  @ViewBuilder
  private var quickOptions: some View {
    switch model.preferences.downloadMode {
    case .automatic, .mute:
      HStack {
        Text("Quality")
          .foregroundStyle(.secondary)
        Spacer()
        Picker("Quality", selection: $model.preferences.videoQuality) {
          ForEach(VideoQuality.allCases) { quality in
            Text(quality.displayName).tag(quality)
          }
        }
        .labelsHidden()
        .frame(width: 140)
      }
    case .audio:
      HStack {
        Label("Best available AAC · M4A", systemImage: "waveform")
          .foregroundStyle(.secondary)
        Spacer()
      }
    }
  }

}
