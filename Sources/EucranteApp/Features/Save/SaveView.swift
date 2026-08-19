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
            .lineLimit(1)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
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
      HStack {
        Label("Best available AAC · M4A", systemImage: "waveform")
          .foregroundStyle(.secondary)
        Spacer()
      }
    }
  }

}
