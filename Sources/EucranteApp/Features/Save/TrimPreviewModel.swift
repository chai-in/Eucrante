@preconcurrency import AVFoundation
import AppKit
import Combine
import EucranteCore
import ImageIO

@MainActor
final class TrimPreviewModel: ObservableObject {
  @Published private(set) var thumbnailRevision = UUID()
  @Published private(set) var websiteAttention = false
  @Published private(set) var loading = false
  @Published private(set) var message: String?
  @Published private(set) var frames: [NSImage?] = []
  @Published private(set) var focusLoading = false
  @Published private(set) var focusedFrame: NSImage?
  @Published private(set) var player: AVPlayer?
  @Published private(set) var playing = false
  @Published private(set) var buffering = false
  @Published private(set) var playhead = 0.0
  @Published private(set) var playbackReady = false
  @Published private(set) var playbackMessage: String?
  @Published private(set) var hasVideo = false
  var onAccessFailure: ((URL, LocalAcquisitionError) -> Void)?

  private let session: any SiteSessionStoring
  private let workspace: DownloadWorkspace
  private let resolver: LocalMediaAcquirer?
  private var source: URL?
  private var audioOnly = false
  private var media: TimelineMedia?
  private var asset: AVURLAsset?
  private var token = UUID()
  private var loadTask: Task<Void, Never>?
  private var stripTask: Task<Void, Never>?
  private var focusTask: Task<Void, Never>?
  private var seekTask: Task<Void, Never>?
  private var readyTimeout: Task<Void, Never>?
  private var statusObservation: NSKeyValueObservation?
  private var timeObserver: Any?
  private var sheets: [URL: CGImage] = [:]
  private var cachedFrames: [Int: NSImage] = [:]
  private var selectionEnd = 0.0
  private var selectionStart = 0.0
  private let network: URLSession

  init(
    session: any SiteSessionStoring, workspace: DownloadWorkspace,
    resolver: LocalMediaAcquirer? = LocalMediaAcquirer()
  ) {
    self.session = session
    self.workspace = workspace
    self.resolver = resolver
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 12
    config.timeoutIntervalForResource = 20
    config.httpCookieStorage = nil
    config.urlCache = nil
    network = URLSession(configuration: config)
  }

  func load(source: URL, audioOnly: Bool, force: Bool = false) {
    if self.source == source, self.audioOnly == audioOnly, !force { return }
    reset()
    self.source = source
    self.audioOnly = audioOnly
    guard let resolver else {
      message = "Preview unavailable for this source."
      return
    }
    loading = true
    let current = token
    loadTask = Task { [weak self] in
      guard let self else { return }
      let directory = workspace.jobs.appendingPathComponent(".preview-timeline-\(current)")
      defer {
        try? FileManager.default.removeItem(at: directory)
        if token == current { loading = false }
      }
      do {
        try SecureCredentialFile.prepareDirectory(directory)
        let cookie = try await session.exportCookieFile(for: source, to: directory)
        try Task.checkCancellation()
        let result = try await resolver.timelineMedia(
          sourceURL: source, cookieFile: cookie, workingDirectory: directory, audioOnly: audioOnly)
        try Task.checkCancellation()
        guard token == current else { return }
        media = result
        if let url = result.videoURL { asset = AVURLAsset(url: url) }
        thumbnailRevision = UUID()
        var refusal: Int?
        var usable: TimelineMedia.Stream?
        for stream in result.playbackStreams {
          try Task.checkCancellation()
          var request = URLRequest(url: stream.url)
          request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
          if let agent = stream.userAgent {
            request.setValue(agent, forHTTPHeaderField: "User-Agent")
          }
          do {
            let (bytes, response) = try await network.bytes(for: request)
            bytes.task.cancel()
            if let response = response as? HTTPURLResponse {
              if (200...299).contains(response.statusCode) {
                usable = stream
                break
              }
              if [401, 403].contains(response.statusCode) { refusal = response.statusCode }
            }
          } catch { try Task.checkCancellation() }
        }
        try Task.checkCancellation()
        guard token == current else { return }
        if let usable {
          var options: [String: Any] = [:]
          if let agent = usable.userAgent { options[AVURLAssetHTTPUserAgentKey] = agent }
          let playbackAsset = AVURLAsset(url: usable.url, options: options)
          if !audioOnly && result.storyboard == nil {
            asset = playbackAsset
            thumbnailRevision = UUID()
          }
          installPlayer(AVPlayerItem(asset: playbackAsset), hasVideo: !audioOnly)
        } else {
          websiteAttention = refusal != nil
          playbackMessage =
            refusal == nil
            ? "Playback preview unavailable for this source. You can still trim and save."
            : "The website refused the preview stream. Open its website session or refresh the preview."
          if refusal == 401 { onAccessFailure?(source, .authenticationRequired) }
        }
        if result.storyboard == nil && result.videoURL == nil {
          message =
            audioOnly
            ? "Audio preview · no video frames available." : "Thumbnail preview unavailable."
        }
      } catch {
        guard token == current, !Task.isCancelled else { return }
        message = "Preview unavailable. You can still set the times and save."
        playbackMessage = "Refresh preview to try again."
        if let failure = error as? LocalAcquisitionError {
          if failure == .authenticationRequired {
            message = "This website requires a refreshed sign-in for preview."
            onAccessFailure?(source, failure)
          }
        }
      }
    }
  }

  /// Also used by deterministic playback tests with a local media fixture.
  func installPlayer(_ item: AVPlayerItem, hasVideo: Bool) {
    let player = AVPlayer(playerItem: item)
    player.automaticallyWaitsToMinimizeStalling = true
    item.preferredForwardBufferDuration = 3
    item.preferredPeakBitRate = 1_500_000
    self.player = player
    self.hasVideo = hasVideo
    let current = token
    statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
      let status = item.status
      Task { @MainActor [weak self] in
        guard let self, token == current else { return }
        playbackReady = status == .readyToPlay
        if playbackReady {
          playbackMessage = nil
          readyTimeout?.cancel()
        }
        if status == .failed {
          pause()
          playbackMessage =
            "The website could not stream this preview. Refresh preview to retry; trimming is still available."
        }
      }
    }
    readyTimeout = Task { [weak self] in
      try? await Task.sleep(for: .seconds(20))
      guard let self, !Task.isCancelled, token == current, !playbackReady else { return }
      pause()
      playbackMessage = "The preview stream is not responding. Refresh preview to retry."
    }
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main
    ) { [weak self] time in
      Task { @MainActor [weak self] in
        guard let self, token == current else { return }
        if playing {
          let seconds = time.seconds
          if seconds.isFinite { playhead = min(selectionEnd, max(selectionStart, seconds)) }
          buffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
          if seconds >= selectionEnd - 0.015 { pause() }
        }
      }
    }
  }

  func setSelection(start: Double, end: Double) {
    pause()
    selectionStart = start
    selectionEnd = end
    player?.currentItem?.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 1000)
    playhead = min(end, max(start, playhead))
  }

  func playSelection(start: Double, end: Double) {
    guard playbackReady, let player, start.isFinite, end.isFinite, end > start else { return }
    setSelection(start: start, end: end)
    let current = token
    seekTask = Task { [weak self] in
      let completed = await player.seek(
        to: CMTime(seconds: start, preferredTimescale: 1000),
        toleranceBefore: .zero, toleranceAfter: .zero)
      guard let self, completed, !Task.isCancelled, token == current else { return }
      playhead = start
      playing = true
      player.play()
    }
  }

  func seek(to time: Double) {
    guard time.isFinite else { return }
    pause()
    playhead = max(0, time)
    player?.currentItem?.forwardPlaybackEndTime = .invalid
    player?.seek(
      to: CMTime(seconds: max(0, time), preferredTimescale: 1000),
      toleranceBefore: .zero, toleranceAfter: .zero)
  }

  func pause() {
    seekTask?.cancel()
    seekTask = nil
    player?.pause()
    playing = false
    buffering = false
  }

  func stop(source input: String) {
    guard source?.absoluteString == (try? SourceURLValidator.validate(input))?.absoluteString else {
      return
    }
    reset()
  }

  func reset() {
    token = UUID()
    loadTask?.cancel()
    stripTask?.cancel()
    focusTask?.cancel()
    pause()
    readyTimeout?.cancel()
    statusObservation = nil
    if let timeObserver { player?.removeTimeObserver(timeObserver) }
    timeObserver = nil
    player?.replaceCurrentItem(with: nil)
    player = nil
    asset?.cancelLoading()
    asset = nil
    media = nil
    source = nil
    sheets.removeAll()
    cachedFrames.removeAll()
    frames = []
    focusedFrame = nil
    focusLoading = false
    loading = false
    message = nil
    playbackMessage = nil
    playbackReady = false
    websiteAttention = false
    playhead = 0
  }

  func showFrames(at times: [Double]) {
    stripTask?.cancel()
    frames = Array(repeating: nil, count: times.count)
    guard media != nil else { return }
    let current = token
    stripTask = Task { [weak self] in
      guard let self else { return }
      try? await Task.sleep(for: .milliseconds(180))
      for (index, time) in times.enumerated() {
        guard !Task.isCancelled, token == current else { return }
        let frame = await thumbnail(at: time)
        guard !Task.isCancelled, token == current else { return }
        frames[index] = frame
      }
      if frames.allSatisfy({ $0 == nil }) {
        message = "Thumbnail preview unavailable. Timestamps still control the saved range."
      }
    }
  }

  func focus(at time: Double?) {
    focusTask?.cancel()
    focusedFrame = nil
    focusLoading = time != nil
    guard let time else { return }
    let current = token
    focusTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(100))
      guard let self, !Task.isCancelled, token == current else { return }
      let frame = await thumbnail(at: time)
      guard !Task.isCancelled, token == current else { return }
      focusedFrame = frame
      focusLoading = false
    }
  }

  private func thumbnail(at seconds: Double) async -> NSImage? {
    guard seconds.isFinite, seconds >= 0, seconds < 10_000_000 else { return nil }
    let key = Int(seconds * 4)
    if let image = cachedFrames[key] { return image }
    do {
      let image: CGImage
      if let storyboard = media?.storyboard, let frame = storyboard.frame(at: seconds) {
        let url = storyboard.sheets[frame.sheet].url
        let sheet: CGImage
        if let cached = sheets[url] {
          sheet = cached
        } else {
          var request = URLRequest(url: url)
          request.cachePolicy = .reloadIgnoringLocalCacheData
          let (bytes, response) = try await network.bytes(for: request)
          defer { bytes.task.cancel() }
          guard let response = response as? HTTPURLResponse, response.statusCode == 200,
            response.expectedContentLength <= 8 * 1024 * 1024
          else { return nil }
          var data = Data()
          for try await byte in bytes {
            data.append(byte)
            if data.count > 8 * 1024 * 1024 { return nil }
          }
          try Task.checkCancellation()
          guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let decoded = CGImageSourceCreateThumbnailAtIndex(
              source, 0,
              [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
              ] as CFDictionary)
          else { return nil }
          sheet = decoded
          if sheets.count >= 4 { sheets.removeAll() }
          sheets[url] = decoded
        }
        let width = Double(sheet.width) / Double(storyboard.columns)
        let height = Double(sheet.height) / Double(storyboard.rows)
        guard
          let cropped = sheet.cropping(
            to: CGRect(
              x: Double(frame.column) * width, y: Double(frame.row) * height, width: width,
              height: height))
        else { return nil }
        image = cropped
      } else if let asset {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 220)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        let deadline = Task {
          try await Task.sleep(for: .seconds(8))
          generator.cancelAllCGImageGeneration()
        }
        defer { deadline.cancel() }
        image = try await withTaskCancellationHandler {
          try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        } onCancel: {
          generator.cancelAllCGImageGeneration()
        }
      } else {
        return nil
      }
      try Task.checkCancellation()
      let result = NSImage(cgImage: image, size: .zero)
      if cachedFrames.count >= 128 { cachedFrames.removeAll() }
      cachedFrames[key] = result
      return result
    } catch { return nil }
  }
}
