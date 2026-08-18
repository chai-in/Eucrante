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
      VStack(spacing: 24) {
        VStack(spacing: 6) {
          Text("Save something you love")
            .font(.system(size: 28, weight: .semibold))
          Text("Choose a ready-made Apple output or open Custom controls.")
            .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)

        VStack(spacing: 18) {
          sourceField

          if model.isEndpointConfigured {
            VStack(alignment: .leading, spacing: 10) {
              Text("One-click outputs")
                .font(.headline)
              LazyVGrid(columns: presetColumns, spacing: 10) {
                presetButton(.appleMusicBest, icon: "music.note")
                presetButton(.appleMusicEfficient, icon: "waveform.badge.minus")
                presetButton(.appleVideoBest, icon: "film")
                presetButton(.appleVideoEfficient, icon: "rectangle.compress.vertical")
              }
            }

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
          } else {
            endpointEmptyState
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
      }
      .padding(32)
      .frame(maxWidth: .infinity, minHeight: 500)
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
    .sheet(item: $model.pickerSelection) { selection in
      PickerSheet(model: model, selection: selection)
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
          Text(preset.shortDetail)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
      }
      .padding(12)
      .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.bordered)
    .disabled(!model.canSubmit)
    .accessibilityHint("Starts the save immediately when a valid link is present")
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
      HStack(spacing: 16) {
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
    }
  }

  private var endpointEmptyState: some View {
    VStack(spacing: 8) {
      Label("A processing instance is required", systemImage: "server.rack")
        .font(.headline)
      Text("Add your private Eucrante deployment to begin.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      SettingsLink { Text("Open Processing Settings") }
        .buttonStyle(.borderedProminent)
    }
  }
}

private struct PickerSheet: View {
  @ObservedObject var model: AppModel
  let selection: AppModel.PickerSelection
  @Environment(\.dismiss) private var dismiss
  private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Choose an item").font(.title2.bold())
          Text("This post contains \(selection.response.picker.count) items.")
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button("Done") { dismiss() }
      }
      .padding()
      Divider()

      ScrollView {
        LazyVGrid(columns: columns, spacing: 12) {
          ForEach(Array(selection.response.picker.enumerated()), id: \.element.id) { index, item in
            Button {
              Task { await model.savePickerItem(item, for: selection.jobID) }
            } label: {
              VStack(alignment: .leading, spacing: 8) {
                AsyncImage(url: item.thumb) { image in
                  image.resizable().scaledToFill()
                } placeholder: {
                  ZStack {
                    Color.secondary.opacity(0.12)
                    Image(systemName: mediaIcon(item.type))
                      .font(.largeTitle)
                      .foregroundStyle(.secondary)
                  }
                }
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text("\(item.type.rawValue.capitalized) \(index + 1)")
                  .fontWeight(.medium)
              }
              .padding(10)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(
                .quaternary.opacity(0.35),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
          }
        }
        .padding()
      }
    }
    .frame(minWidth: 560, minHeight: 420)
  }

  private func mediaIcon(_ type: PickerItem.MediaType) -> String {
    switch type {
    case .photo: "photo"
    case .video: "video"
    case .gif: "photo.stack"
    }
  }
}
