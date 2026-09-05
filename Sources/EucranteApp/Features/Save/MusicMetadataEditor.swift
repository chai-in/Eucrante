import AppKit
import EucranteCore
import SwiftUI

struct MusicMetadataEditor: View {
  @ObservedObject var model: AppModel
  @State private var metadataExpanded = false

  var body: some View {
    let automatic = model.mediaPreview?.metadata
    return DisclosureGroup(isExpanded: $metadataExpanded) {
      VStack(spacing: 10) {
        metadataField("Title", text: $model.musicMetadataDraft.title, automatic: automatic?.title)
        metadataField(
          "Artist", text: $model.musicMetadataDraft.artist, automatic: automatic?.artist)
        metadataField("Album", text: $model.musicMetadataDraft.album, automatic: automatic?.album)
        metadataField(
          "Album Artist", text: $model.musicMetadataDraft.albumArtist,
          automatic: automatic?.albumArtist)
        metadataField(
          "Composer", text: $model.musicMetadataDraft.composer, automatic: automatic?.composer)
        metadataField("Genre", text: $model.musicMetadataDraft.genre, automatic: automatic?.genre)

        HStack(spacing: 12) {
          compactMetadataField(
            "Year", text: $model.musicMetadataDraft.year,
            automatic: automatic?.year.map(String.init))
          compactMetadataField(
            "Track", text: $model.musicMetadataDraft.trackNumber,
            automatic: numberedMetadata(automatic?.trackNumber, count: automatic?.trackCount))
          compactMetadataField(
            "Disc", text: $model.musicMetadataDraft.discNumber,
            automatic: numberedMetadata(automatic?.discNumber, count: automatic?.discCount))
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
          } else if let automaticArtwork = automatic?.artworkURL {
            AsyncImage(url: automaticArtwork) { phase in
              if case .success(let image) = phase {
                image.resizable().scaledToFill()
              } else {
                Image(systemName: "photo")
                  .font(.title3)
                  .foregroundStyle(.secondary)
              }
            }
            .frame(width: 44, height: 44)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityLabel("Source artwork")
          } else {
            Image(systemName: "photo")
              .font(.title3)
              .foregroundStyle(.secondary)
              .frame(width: 44, height: 44)
              .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
              .accessibilityHidden(true)
          }

          VStack(alignment: .leading, spacing: 1) {
            Text("Artwork")
              .foregroundStyle(.secondary)
            if model.musicMetadataDraft.artworkURL == nil, automatic?.artworkURL != nil {
              Text("Auto — Source artwork")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            } else if model.musicMetadataDraft.artworkURL == nil, model.mediaPreview != nil {
              Text("Auto — None fetched")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
          }
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

  private func metadataField(
    _ label: String,
    text: Binding<String>,
    automatic: String?
  ) -> some View {
    LabeledContent(label) {
      TextField(metadataPlaceholder(automatic), text: text)
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 380)
    }
  }

  private func compactMetadataField(
    _ label: String,
    text: Binding<String>,
    automatic: String?
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
      TextField(metadataPlaceholder(automatic), text: text)
        .textFieldStyle(.roundedBorder)
    }
  }

  private func metadataPlaceholder(
    _ value: String?,
    fallback: String = "Auto — None fetched"
  ) -> String {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return fallback
    }
    return value
  }

  private func numberedMetadata(_ number: Int?, count: Int?) -> String? {
    guard let number else { return nil }
    guard let count, count > 0 else { return String(number) }
    return "\(number) of \(count)"
  }

}
