import AVFoundation
import AppKit
import EucranteCore
import SwiftUI

struct TimeRangeEditor: View {
  @ObservedObject var model: AppModel

  var body: some View {
    if let duration = model.mediaPreview?.duration, duration.isFinite, duration > 0,
      duration < 10_000_000
    {
      TrimEditorView(model: model, preview: model.trimPreview, duration: duration)
        .id(model.sourceText)
    } else {
      VStack(alignment: .leading, spacing: 8) {
        Text("Time range").font(.headline)
        HStack {
          TextField("Start · 0:00", text: $model.startTime).accessibilityLabel("Start time")
          Text("to").foregroundStyle(.secondary)
          TextField("End · full length", text: $model.endTime).accessibilityLabel("End time")
        }.textFieldStyle(.roundedBorder)
        Text("The visual timeline appears when the source duration is available.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}

private struct TrimEditorView: View {
  @ObservedObject var model: AppModel
  @ObservedObject var preview: TrimPreviewModel
  let duration: Double
  let sourceText: String
  @State private var geometry: TrimTimelineGeometry
  @State private var hoverTime: Double?
  @State private var dragging = false
  @FocusState private var focusedEdge: Edge?
  private enum Edge: Hashable { case start, end }

  init(model: AppModel, preview: TrimPreviewModel, duration: Double) {
    self.model = model
    self.preview = preview
    self.duration = duration
    self.sourceText = model.sourceText
    _geometry = State(initialValue: TrimTimelineGeometry(duration: duration))
  }

  private var range: (Double, Double)? {
    TrimTimelineGeometry.bounds(start: model.startTime, end: model.endTime, duration: duration)
  }
  private var start: Double { range?.0 ?? 0 }
  private var end: Double { range?.1 ?? duration }
  private var waitingForPlayer: Bool {
    preview.player != nil && !preview.playbackReady && preview.playbackMessage == nil
  }
  private var audioOnly: Bool {
    model.selectedPreset.isAudio
      || (model.selectedPreset == .custom && model.preferences.downloadMode == .audio)
  }
  private var times: [Double] {
    (0..<8).map { geometry.time(at: (Double($0) + 0.5) / 8) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Trim & preview").font(.headline)
        Spacer()
        Button("Reset to full length") {
          model.startTime = ""
          model.endTime = ""
          geometry = TrimTimelineGeometry(duration: duration)
          preview.seek(to: 0)
        }
      }
      playback
      timeline
      HStack {
        Text(TrimTimelineGeometry.timestamp(geometry.origin))
        Spacer()
        Text("Drag edges to trim · click to inspect")
        Spacer()
        Text(TrimTimelineGeometry.timestamp(geometry.upper))
      }.font(.caption2).foregroundStyle(.secondary).monospacedDigit()
      zoomControls
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Start").font(.caption).foregroundStyle(.secondary)
          TextField("0:00", text: $model.startTime).accessibilityLabel("Start time")
        }
        VStack(alignment: .leading, spacing: 4) {
          Text("End").font(.caption).foregroundStyle(.secondary)
          TextField(TrimTimelineGeometry.timestamp(duration), text: $model.endTime)
            .accessibilityLabel("End time")
        }
        VStack(alignment: .leading, spacing: 4) {
          Text("Selected duration").font(.caption).foregroundStyle(.secondary)
          Text(range == nil ? "Invalid range" : TrimTimelineGeometry.timestamp(end - start))
            .monospacedDigit().frame(height: 22)
        }
      }.textFieldStyle(.roundedBorder)
      if range == nil {
        Text("Enter a start and end within this item, with end after start.")
          .font(.caption).foregroundStyle(.red)
      }
      HStack {
        Text("Position \(TrimTimelineGeometry.timestamp(preview.playhead))").monospacedDigit()
        Spacer()
        Button("Set start here") { change(.start, to: preview.playhead) }
        Button("Set end here") { change(.end, to: preview.playhead) }
      }.font(.caption)
      HStack {
        Button {
          if preview.playing {
            preview.pause()
          } else {
            preview.playSelection(start: start, end: end)
          }
        } label: {
          Label(
            preview.playing ? "Pause preview" : "Preview selection",
            systemImage: preview.playing ? "pause.fill" : "play.fill")
        }.disabled(!preview.playbackReady || range == nil)
        if preview.loading || preview.buffering || waitingForPlayer {
          ProgressView().controlSize(.small)
        }
        Text(
          preview.loading
            ? "Loading preview…"
            : waitingForPlayer ? "Connecting preview…" : preview.buffering ? "Buffering…" : ""
        )
        .font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Refresh preview") { load(force: true) }.disabled(preview.loading)
      }
      if preview.websiteAttention, let source = try? SourceURLValidator.validate(sourceText) {
        Button("Open \(MediaSite(source).name) website…") { model.openSiteSignIn(source) }
      }
      if let message = preview.playbackMessage ?? preview.message {
        Text(message).font(.caption).foregroundStyle(.secondary)
      }
      Text(
        "Preview frames are approximate. Save uses your timestamps. Arrow keys adjust a focused edge by 1 second; Shift adjusts by 0.1 second. The full source downloads before trimming."
      )
      .font(.caption).foregroundStyle(.secondary)
    }
    .onAppear { load() }
    .onChange(of: audioOnly) { load() }
    .onChange(of: model.timelineRevision) { load(force: true) }
    .onChange(of: preview.thumbnailRevision) { preview.showFrames(at: times) }
    .onChange(of: geometry) { preview.showFrames(at: times) }
    .onChange(of: model.startTime) { updateSelection() }
    .onChange(of: model.endTime) { updateSelection() }
    .onDisappear { preview.stop(source: sourceText) }
  }

  @ViewBuilder private var playback: some View {
    if !audioOnly, let player = preview.player {
      PreviewPlayerSurface(player: player)
        .frame(height: 190).background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("Video preview")
    } else if audioOnly {
      HStack(spacing: 12) {
        AsyncImage(url: model.mediaPreview?.metadata.artworkURL) { image in
          image.resizable().scaledToFit()
        } placeholder: {
          Image(systemName: "waveform").font(.title)
        }
        .frame(width: 44, height: 44)
        Text("Audio selection preview").font(.callout).foregroundStyle(.secondary)
      }
    }
  }

  private var timeline: some View {
    GeometryReader { proxy in
      let width = max(1, proxy.size.width)
      let left = min(width, max(0, geometry.fraction(at: start) * width))
      let right = min(width, max(0, geometry.fraction(at: end) * width))
      ZStack(alignment: .topLeading) {
        HStack(spacing: 1) {
          ForEach(0..<8, id: \.self) { index in
            ZStack {
              Rectangle().fill(.quaternary)
              if preview.frames.indices.contains(index), let image = preview.frames[index] {
                Image(nsImage: image).resizable().scaledToFill()
              } else {
                Image(systemName: audioOnly ? "waveform" : "film").foregroundStyle(.secondary)
              }
            }.frame(width: max(0, (width - 7) / 8), height: 62).clipped()
          }
        }.clipShape(RoundedRectangle(cornerRadius: 6))
        Rectangle().fill(.black.opacity(0.6)).frame(width: left, height: 62)
        Rectangle().fill(.black.opacity(0.6)).frame(width: max(0, width - right), height: 62)
          .offset(x: right)
        Rectangle().stroke(Color.accentColor, lineWidth: 2)
          .frame(width: max(0, right - left), height: 62).offset(x: left)
        if (geometry.origin...geometry.upper).contains(preview.playhead) {
          Rectangle().fill(.white).frame(width: 2, height: 70)
            .offset(x: geometry.fraction(at: preview.playhead) * width, y: -4)
        }
        if (geometry.origin...geometry.upper).contains(start) {
          handle(.start, width: width, height: right - left < 28 ? 30 : 62)
            .offset(x: min(width - 14, max(0, left - 7)))
        }
        if (geometry.origin...geometry.upper).contains(end) {
          handle(.end, width: width, height: right - left < 28 ? 30 : 62)
            .offset(x: min(width - 14, max(0, right - 7)), y: right - left < 28 ? 32 : 0)
        }
      }
      .contentShape(Rectangle())
      .coordinateSpace(name: "trimRoot")
      .gesture(
        DragGesture(minimumDistance: 0).onChanged { value in
          let time = geometry.time(at: value.location.x / width)
          preview.seek(to: time)
          inspect(time)
        }.onEnded { _ in inspect(nil) }
      )
      .onContinuousHover { phase in
        guard !dragging else { return }
        switch phase {
        case .active(let location): inspect(geometry.time(at: location.x / width))
        case .ended: inspect(nil)
        }
      }
      .overlay(alignment: .topLeading) {
        if let hoverTime {
          VStack(spacing: 5) {
            if let image = preview.focusedFrame {
              Image(nsImage: image).resizable().scaledToFit().frame(width: 160, height: 90)
            } else if preview.focusLoading {
              ProgressView().controlSize(.small).frame(width: 160, height: 60)
            } else {
              Text("Preview unavailable").font(.caption).frame(width: 160, height: 60)
            }
            Text(TrimTimelineGeometry.timestamp(hoverTime)).font(.caption.monospacedDigit())
            Text("Approximate frame").font(.caption2).foregroundStyle(.secondary)
          }
          .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
          .offset(
            x: min(max(0, geometry.fraction(at: hoverTime) * width - 88), max(0, width - 176)),
            y: -142
          )
          .allowsHitTesting(false)
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Trim timeline")
    }.frame(height: 62)
  }

  private func handle(_ edge: Edge, width: Double, height: Double) -> some View {
    RoundedRectangle(cornerRadius: 4)
      .fill(focusedEdge == edge ? Color.orange : Color.accentColor)
      .overlay(
        Image(systemName: "line.3.horizontal").rotationEffect(.degrees(90)).font(.system(size: 10))
      )
      .frame(width: 14, height: height)
      .contentShape(Rectangle())
      .focusable().focused($focusedEdge, equals: edge)
      .highPriorityGesture(
        DragGesture(minimumDistance: 0, coordinateSpace: .named("trimRoot"))
          .onChanged { value in
            focusedEdge = edge
            dragging = true
            change(edge, to: geometry.time(at: value.location.x / width))
            inspect(edge == .start ? start : end)
          }.onEnded { _ in
            dragging = false
            inspect(nil)
          }
      )
      .onKeyPress(keys: [.leftArrow, .rightArrow]) { key in
        let increment = key.modifiers.contains(.shift) ? 0.1 : 1.0
        change(
          edge,
          to: (edge == .start ? start : end) + (key.key == .leftArrow ? -increment : increment))
        inspect(edge == .start ? start : end)
        return .handled
      }
      .accessibilityLabel(edge == .start ? "Trim start handle" : "Trim end handle")
      .accessibilityValue(TrimTimelineGeometry.timestamp(edge == .start ? start : end))
      .accessibilityAdjustableAction { direction in
        change(edge, to: (edge == .start ? start : end) + (direction == .increment ? 1 : -1))
      }
  }

  private var zoomControls: some View {
    VStack(spacing: 5) {
      HStack {
        Button {
          zoom(geometry.zoom / 2)
        } label: {
          Image(systemName: "minus.magnifyingglass")
        }
        .accessibilityLabel("Zoom out").disabled(geometry.zoom <= 1)
        Slider(
          value: Binding(get: { geometry.zoom }, set: { zoom($0) }),
          in: 1...max(1.001, geometry.maximumZoom)
        )
        .accessibilityLabel("Timeline zoom").disabled(geometry.maximumZoom <= 1)
        Button {
          zoom(geometry.zoom * 2)
        } label: {
          Image(systemName: "plus.magnifyingglass")
        }
        .accessibilityLabel("Zoom in").disabled(geometry.zoom >= geometry.maximumZoom)
        Text(String(format: "%.1f×", geometry.zoom)).font(.caption).monospacedDigit().frame(
          width: 42)
        Button("Fit selection") {
          geometry.setZoom(duration / max(0.1, (end - start) * 1.15), around: (start + end) / 2)
        }.disabled(range == nil)
        Button("Full view") { geometry.setZoom(1, around: duration / 2) }
      }
      if geometry.zoom > 1 {
        Slider(value: $geometry.origin, in: 0...max(0.001, duration - geometry.span))
          .accessibilityLabel("Timeline visible position")
      }
    }
  }

  private func change(_ edge: Edge, to time: Double) {
    let gap = min(0.01, duration / 2)
    if edge == .start {
      model.startTime = TrimTimelineGeometry.timestamp(min(max(0, time), end - gap))
    } else {
      model.endTime = TrimTimelineGeometry.timestamp(max(min(duration, time), start + gap))
    }
    preview.seek(to: edge == .start ? start : end)
  }

  private func updateSelection() {
    if let range { preview.setSelection(start: range.0, end: range.1) } else { preview.pause() }
  }
  private func zoom(_ value: Double) {
    let center =
      (geometry.origin...geometry.upper).contains(preview.playhead)
      ? preview.playhead : geometry.origin + geometry.span / 2
    geometry.setZoom(value, around: center)
  }
  private func inspect(_ time: Double?) {
    hoverTime = time
    preview.focus(at: time)
  }
  private func load(force: Bool = false) {
    guard let source = try? SourceURLValidator.validate(sourceText) else { return }
    preview.load(source: source, audioOnly: audioOnly, force: force)
  }
}

private struct PreviewPlayerSurface: NSViewRepresentable {
  let player: AVPlayer
  func makeNSView(context: Context) -> PlayerView { PlayerView() }
  func updateNSView(_ view: PlayerView, context: Context) { view.playerLayer.player = player }
  static func dismantleNSView(_ view: PlayerView, coordinator: ()) { view.playerLayer.player = nil }

  final class PlayerView: NSView {
    let playerLayer = AVPlayerLayer()
    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      wantsLayer = true
      layer = playerLayer
      playerLayer.videoGravity = .resizeAspect
    }
    required init?(coder: NSCoder) { nil }
  }
}
