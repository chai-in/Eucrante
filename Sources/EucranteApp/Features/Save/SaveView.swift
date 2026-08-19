import AppKit
import EucranteCore
import SwiftUI

struct SaveView: View {
  @ObservedObject var model: AppModel
  @FocusState private var sourceFocused: Bool
  @State private var customExpanded = false
  @State private var metadataExpanded = false

  private let presetColumns = [
    GridItem(.flexible(), spacing: 10),
    GridItem(.flexible(), spacing: 10),
  ]

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        VStack(spacing: 18) {
          sourceField
          mediaPreview

          LazyVGrid(columns: presetColumns, spacing: 10) {
            presetButton(.appleMusicBest, icon: "music.note")
            presetButton(.appleMusicEfficient, icon: "waveform.badge.minus")
            presetButton(.appleVideoBest, icon: "film")
            presetButton(.appleVideoEfficient, icon: "rectangle.compress.vertical")
          }

          musicMetadataEditor

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
        .eucranteCard()
        .frame(maxWidth: 600)

        HStack(spacing: 8) {
          Image(systemName: "folder")
          Text(model.destinationDirectory.path(percentEncoded: false))
            .lineLimit(1)
            .truncationMode(.middle)
          Button("Choose…") { model.chooseDestinationDirectory() }
            .buttonStyle(.link)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: 600, alignment: .leading)
      }
      .padding(.horizontal, 32)
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

  private var musicMetadataEditor: some View {
    DisclosureGroup(isExpanded: $metadataExpanded) {
      VStack(spacing: 10) {
        metadataField("Title", text: $model.musicMetadataDraft.title)
        metadataField("Artist", text: $model.musicMetadataDraft.artist)
        metadataField("Album", text: $model.musicMetadataDraft.album)
        metadataField("Album Artist", text: $model.musicMetadataDraft.albumArtist)
        metadataField("Composer", text: $model.musicMetadataDraft.composer)
        metadataField("Genre", text: $model.musicMetadataDraft.genre)

        HStack(spacing: 12) {
          compactMetadataField("Year", text: $model.musicMetadataDraft.year)
          compactMetadataField("Track", text: $model.musicMetadataDraft.trackNumber)
          compactMetadataField("Disc", text: $model.musicMetadataDraft.discNumber)
        }

        HStack(spacing: 10) {
          if let url = model.musicMetadataDraft.artworkURL,
            let image = NSImage(contentsOf: url)
          {
            Image(nsImage: image)
              .resizable()
              .scaledToFill()
              .frame(width: 44, height: 44)
              .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
              .accessibilityLabel("Selected artwork")
          } else {
            Image(systemName: "photo")
              .font(.title3)
              .foregroundStyle(.secondary)
              .frame(width: 44, height: 44)
              .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
              .accessibilityHidden(true)
          }

          Text("Artwork")
            .foregroundStyle(.secondary)
          Spacer()
          Button("Choose…") { model.chooseMusicArtwork() }
          if model.musicMetadataDraft.artworkURL != nil {
            Button {
              model.musicMetadataDraft.artworkURL = nil
            } label: {
              Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Remove selected artwork")
          }
        }

        if !model.musicMetadataDraft.isEmpty {
          HStack {
            Spacer()
            Button("Clear Metadata") { model.clearMusicMetadata() }
              .buttonStyle(.link)
          }
        }
      }
      .padding(.top, 12)
    } label: {
      Label("Music metadata", systemImage: "music.note.list")
    }
  }

  private func metadataField(_ label: String, text: Binding<String>) -> some View {
    LabeledContent(label) {
      TextField("Automatic", text: text)
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 380)
    }
  }

  private func compactMetadataField(_ label: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
      TextField("Auto", text: text)
        .textFieldStyle(.roundedBorder)
    }
  }

  private var sourceField: some View {
    HStack(spacing: 10) {
      Image(systemName: "link")
        .foregroundStyle(.secondary)
      TextField("https://…", text: $model.sourceText)
        .textFieldStyle(.plain)
        .font(.body)
        .focused($sourceFocused)
        .onSubmit { Task { await model.submit(preset: .custom) } }
        .accessibilityLabel("Public media link")
      if !model.sourceText.isEmpty {
        Button {
          model.sourceText = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear link")
      }
    }
    .padding(.horizontal, 14)
    .frame(height: 44)
    .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
          .lineLimit(2)
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
        minHeight: model.mediaPreview == nil ? 52 : 68,
        alignment: .leading
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.bordered)
    .disabled(!model.canSubmit)
    .accessibilityHint("Starts the save immediately when a valid link is present")
  }

  private func presetDetail(_ preset: EucrantePreset) -> String? {
    guard let output = model.mediaPreview?.output(for: preset) else { return nil }
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
      let total = Int(duration.rounded())
      parts.append(String(format: "%d:%02d", total / 60, total % 60))
    }
    parts.append("\(preview.formats.count) formats")
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
