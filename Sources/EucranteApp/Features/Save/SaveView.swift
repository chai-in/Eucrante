import EucranteCore
import SwiftUI

struct SaveView: View {
  @ObservedObject var model: AppModel
  @FocusState private var sourceFocused: Bool

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        Spacer(minLength: 16)

        VStack(spacing: 6) {
          Text("Save something you love")
            .font(.system(size: 28, weight: .semibold))
          Text("Public links only. Your files stay on this Mac.")
            .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)

        VStack(spacing: 18) {
          HStack(spacing: 10) {
            Image(systemName: "link")
              .foregroundStyle(.secondary)
            TextField("https://…", text: $model.sourceText)
              .textFieldStyle(.plain)
              .font(.body)
              .focused($sourceFocused)
              .onSubmit { Task { await model.submit() } }
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

          Picker("Mode", selection: $model.preferences.downloadMode) {
            Label("Auto", systemImage: "sparkles").tag(DownloadMode.automatic)
            Label("Audio", systemImage: "waveform").tag(DownloadMode.audio)
            Label("Mute", systemImage: "speaker.slash").tag(DownloadMode.mute)
          }
          .pickerStyle(.segmented)
          .labelsHidden()

          quickOptions

          if model.isEndpointConfigured {
            Button {
              Task { await model.submit() }
            } label: {
              HStack(spacing: 8) {
                if model.isSubmitting {
                  ProgressView().controlSize(.small)
                }
                Text(model.isSubmitting ? "Saving…" : "Save")
                  .fontWeight(.semibold)
              }
              .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canSubmit)
            .keyboardShortcut(.defaultAction)
          } else {
            VStack(spacing: 8) {
              Label("A processing instance is required", systemImage: "server.rack")
                .font(.headline)
              Text(
                "Cobalt’s public API is not intended for third-party clients. Add your private instance to continue."
              )
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
              SettingsLink {
                Text("Open Processing Settings")
              }
              .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
          }
        }
        .eucranteCard()
        .frame(maxWidth: 560)

        HStack(spacing: 6) {
          Image(systemName: "folder")
          Text(model.destinationDirectory.path(percentEncoded: false))
            .lineLimit(1)
            .truncationMode(.middle)
        }
        .font(.caption)
        .foregroundStyle(.secondary)

        Spacer(minLength: 16)
      }
      .padding(32)
      .frame(maxWidth: .infinity, minHeight: 500)
    }
    .navigationTitle("Save")
    .onAppear { sourceFocused = true }
    .onChange(of: model.focusRequestID) { sourceFocused = true }
    .sheet(item: $model.pickerSelection) { selection in
      PickerSheet(model: model, selection: selection)
    }
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
          Text("Choose an item")
            .font(.title2.bold())
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
