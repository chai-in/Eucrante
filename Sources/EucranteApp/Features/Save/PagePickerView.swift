import EucranteCore
import SwiftUI

struct PagePickerView: View {
  @ObservedObject var model: AppModel
  @ObservedObject var picker: PagePickerModel
  @State private var showUnavailable = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Choose from this page").font(.title2.bold())
          Text(picker.title).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer()
        Button("Done") { model.showingPagePicker = false }.keyboardShortcut(.cancelAction)
      }
      HStack {
        if picker.running { ProgressView().controlSize(.small) }
        Text(
          "\(picker.rows.filter { $0.preview != nil }.count) verified · \(picker.rows.count) found")
        if !picker.running {
          Text(String(format: "· %.1f s", picker.elapsed)).foregroundStyle(.secondary)
        }
        Spacer()
        Toggle("Show unavailable", isOn: $showUnavailable).toggleStyle(.checkbox)
      }.font(.callout)
      Text(
        "Hover or focus an item to inspect its source, duration and size. Click to edit before saving."
      )
      .font(.caption).foregroundStyle(.secondary)
      if picker.truncated {
        Text(
          "Showing the first 100 links or 55 KB of page results. Scroll the page and run the button again for newly loaded items."
        )
        .font(.caption).foregroundStyle(.orange)
      }
      List {
        ForEach(
          picker.rows.filter {
            showUnavailable || $0.error == nil || $0.failure == .authenticationRequired
          }
        ) { row in
          PagePickerRow(row: row) {
            model.selectPageItem(row)
          }
        }
      }.listStyle(.inset).frame(minHeight: 280)
      ForEach(
        Array(
          Set(
            picker.rows.filter { $0.failure == .authenticationRequired }.map {
              MediaSite($0.item.url)
            })
        ).sorted { $0.host < $1.host }
      ) { site in
        HStack {
          Text("\(site.name) requires a fresh sign-in to verify some items.")
            .font(.caption).foregroundStyle(.secondary)
          Spacer()
          Button("Reconnect \(site.name)") {
            model.openSiteSignIn(
              picker.rows.first {
                MediaSite($0.item.url) == site && $0.failure == .authenticationRequired
              }?.item.url)
          }
        }
      }
      if picker.rows.contains(where: { $0.error != nil }), !picker.running {
        HStack {
          Text("Unavailable items include a reason. Turn on Show unavailable to inspect them.")
            .font(.caption).foregroundStyle(.secondary)
          Spacer()
          Button("Retry Unavailable") { picker.retryFailures() }
        }
      }

    }.padding(24).frame(width: 730, height: 570)
  }
}

private struct PagePickerRow: View {
  let row: PagePickerModel.Row
  let select: () -> Void
  @State private var hovered = false
  @FocusState private var focused: Bool

  var body: some View {
    Button(action: select) {
      HStack(spacing: 12) {
        AsyncImage(url: row.preview?.metadata.artworkURL) { image in
          image.resizable().scaledToFit()
        } placeholder: {
          Image(systemName: "play.rectangle").font(.title2).foregroundStyle(.secondary)
        }.frame(width: 88, height: 56)
        VStack(alignment: .leading, spacing: 4) {
          Text(
            row.preview?.metadata.title
              ?? (row.item.title.isEmpty ? row.item.url.absoluteString : row.item.title)
          )
          .font(.headline).lineLimit(2)
          if let preview = row.preview {
            Text(
              [preview.metadata.artist, preview.duration.map(Self.duration)].compactMap { $0 }
                .joined(separator: " · ")
            )
            .font(.caption).foregroundStyle(.secondary)
          } else {
            Text(row.error ?? (row.checking ? "Checking availability…" : "Waiting to verify…"))
              .font(.caption).foregroundStyle(.secondary).lineLimit(2)
          }
        }
        Spacer()
        if row.checking { ProgressView().controlSize(.small) }
        if row.preview != nil { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
      }.padding(.vertical, 7).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(row.preview == nil)
    .focused($focused)
    .onHover { hovered = $0 }
    .accessibilityHint(details)
    .popover(
      isPresented: Binding(
        get: { (hovered || focused) && row.preview != nil },
        set: {
          if !$0 {
            hovered = false
            focused = false
          }
        }), arrowEdge: .trailing
    ) {
      VStack(alignment: .leading, spacing: 10) {
        Text(row.preview?.metadata.title ?? row.item.title).font(.headline)
        Text(details).font(.callout).textSelection(.enabled)
      }.padding(18).frame(width: 340)
    }
  }

  private var details: String {
    var lines = [row.item.url.absoluteString]
    guard let preview = row.preview else { return lines.joined(separator: "\n") }
    if let artist = preview.metadata.artist { lines.append(artist) }
    if let duration = preview.duration { lines.append("Duration: \(Self.duration(duration))") }
    for preset in [
      EucrantePreset.appleMusicBest, .appleMusicEfficient, .appleVideoBest, .appleVideoEfficient,
    ] {
      guard let output = preview.output(for: preset) else { continue }
      let size =
        output.estimatedByteCount.map {
          "\(output.sizeIsEstimate ? "approximately " : "")\(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file))"
        } ?? "size unavailable"
      lines.append(
        "\(preset.displayName): \(output.codec) · \(output.quality ?? output.container) · \(size)")
    }
    return lines.joined(separator: "\n\n")
  }

  private static func duration(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0, seconds < 10_000_000 else { return "Unknown" }
    let value = Int(seconds.rounded())
    return String(format: "%d:%02d", value / 60, value % 60)
  }
}
