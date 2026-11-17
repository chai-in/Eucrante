import AppKit
import EucranteCore
import SwiftUI

struct CoverEditor: View {
  @ObservedObject var model: AppModel
  @State private var sourceData: Data?
  @State private var previewData: Data?
  @State private var message: String?
  @State private var loading = false
  private var url: URL? {
    model.musicMetadataDraft.artworkURL ?? model.mediaPreview?.metadata.artworkURL
  }
  private var renderKey: String {
    "\(url?.absoluteString ?? "")|\(model.coverStyle.rawValue)|\(model.removeBlackBars)"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Square cover").font(.headline)
      HStack(alignment: .top, spacing: 18) {
        Group {
          if let previewData, let image = NSImage(data: previewData) {
            Image(nsImage: image).resizable().scaledToFit()
          } else if loading {
            ProgressView()
          } else {
            Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
          }
        }.frame(width: 180, height: 180)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
          .accessibilityLabel("Cover preview: \(model.coverStyle.displayName)")
        VStack(alignment: .leading, spacing: 12) {
          Picker("Fill", selection: $model.coverStyle) {
            ForEach(CoverStyle.allCases) { style in Text(style.displayName).tag(style) }
          }
          Toggle("Remove embedded black bars", isOn: $model.removeBlackBars)
            .disabled(model.coverStyle == .original)
          Text(
            "Edge gradient continues nearby colours into each empty border. The artwork itself stays sharp and uncropped, except for detected black bars."
          )
          .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          if let message { Text(message).font(.caption).foregroundStyle(.red) }
        }
      }
    }
    .task(id: url) {
      sourceData = nil
      previewData = nil
      message = nil
      guard let url else { return }
      loading = true
      defer { loading = false }
      do {
        let data: Data
        if url.isFileURL {
          guard ArtworkStore.validateSelection(url) else { throw ArtworkStoreError.invalidImage }
          data = try Data(contentsOf: url)
        } else {
          data = try await ArtworkStore.download(from: url)
        }
        try Task.checkCancellation()
        sourceData = data
      } catch {
        if !Task.isCancelled {
          message = "Cover preview unavailable. Choose another image or retry the link."
        }
      }
    }
    .task(id: RenderKey(data: sourceData, options: renderKey)) {
      guard let sourceData else { return }
      let style = model.coverStyle
      let trim = model.removeBlackBars
      let rendered = await Task.detached(priority: .userInitiated) {
        ArtworkNormalizer.jpegData(from: sourceData, style: style, removeBlackBars: trim)
      }.value
      guard !Task.isCancelled else { return }
      previewData = rendered
    }
  }

  private struct RenderKey: Equatable {
    let data: Data?
    let options: String
  }
}
