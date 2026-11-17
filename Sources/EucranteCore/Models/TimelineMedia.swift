import Foundation

/// Short-lived preview resources. Never persisted with history or the page-scan cache.
public struct TimelineMedia: Sendable {
  public let playbackStreams: [Stream]
  public var playbackURL: URL? { playbackStreams.first?.url }
  public struct Stream: Sendable {
    public let url: URL
    public let userAgent: String?
  }
  public let videoURL: URL?
  public let storyboard: Storyboard?

  public struct Storyboard: Sendable {
    public let columns: Int
    public let rows: Int
    public let framesPerSecond: Double
    public let sheets: [Sheet]

    public struct Sheet: Sendable {
      public let url: URL
      public let start: Double
      public let duration: Double
    }

    public func frame(at seconds: Double) -> (sheet: Int, column: Int, row: Int)? {
      guard seconds.isFinite, seconds >= 0,
        let index = sheets.lastIndex(where: { $0.start <= seconds })
      else { return nil }
      // The last sheet may be only partly filled. At the item's end, show its last
      // actual frame rather than an empty cell from the remainder of the grid.
      let count = max(
        1, Int(ceil(min(Double(columns * rows), sheets[index].duration * framesPerSecond))))
      let cell = Int(min(Double(count - 1), (seconds - sheets[index].start) * framesPerSecond))
      return (index, cell % columns, cell / columns)
    }
  }
}

extension LocalMediaAcquirer {
  public func timelineMedia(
    sourceURL: URL, cookieFile: URL?, workingDirectory: URL, audioOnly: Bool
  )
    async throws -> TimelineMedia
  {
    _ = try SourceURLValidator.validate(sourceURL.absoluteString)
    try LocalProcessRunner.prepareRestrictedEnvironment(homeDirectory: workingDirectory)
    var arguments = [
      "--ignore-config", "--no-playlist", "--no-warnings", "--skip-download",
      "--socket-timeout", "12", "--retries", "1", "--extractor-retries", "1",
      "--js-runtimes", "deno:\(tools.deno.path)",
      "--print",
      "%(formats.:.{url,ext,protocol,vcodec,acodec,height,width,fps,rows,columns,fragments,http_headers})j",
    ]
    if let cookieFile { arguments += ["--cookies", cookieFile.path] }
    arguments.append(sourceURL.absoluteString)
    let lines = try await LocalProcessRunner().run(
      executable: tools.ytDLP, arguments: arguments,
      environment: LocalProcessRunner.restrictedEnvironment(homeDirectory: workingDirectory),
      onLine: { _ in })
    try Task.checkCancellation()
    guard
      let formats = lines.reversed().compactMap({ line in
        try? JSONDecoder().decode([TimelineFormat].self, from: Data(line.utf8))
      }).first
    else { throw LocalAcquisitionError.previewUnavailable }
    return Self.timelineSelection(formats, audioOnly: audioOnly)
  }

  static func timelineSelection(_ formats: [TimelineFormat], audioOnly: Bool) -> TimelineMedia {
    let playable = formats.filter { format in
      TimelineFormat.remoteURL(format.url) != nil
        && ["https", "http", "m3u8_native", "m3u8"].contains(format.transport ?? "")
    }
    let video = playable.filter {
      (($0.vcodec == nil && $0.ext == "mp4")
        || $0.vcodec?.hasPrefix("avc") == true || $0.vcodec?.hasPrefix("hvc") == true
        || $0.vcodec?.hasPrefix("hev") == true || $0.vcodec?.hasPrefix("h264") == true)
    }
    let combined = video.filter { $0.acodec == nil || $0.acodec?.hasPrefix("mp4a") == true }
    // Low-bandwidth previews are separate from the final download's quality policy.
    func ordered(_ choices: [TimelineFormat]) -> [TimelineFormat] {
      choices.sorted {
        let leftStream = $0.transport?.hasPrefix("m3u8") == true
        let rightStream = $1.transport?.hasPrefix("m3u8") == true
        if leftStream != rightStream { return !leftStream }
        return abs(($0.height ?? 360) - 360) < abs(($1.height ?? 360) - 360)
      }
    }
    let audio = playable.filter { $0.vcodec == "none" && $0.acodec?.hasPrefix("mp4a") == true }
    let choices = audioOnly ? ordered(audio) + ordered(combined) : ordered(combined)
    let streams = choices.prefix(3).compactMap { format -> TimelineMedia.Stream? in
      guard let url = TimelineFormat.remoteURL(format.url) else { return nil }
      let userAgent = format.headers?["User-Agent"].flatMap { value in
        value.count <= 1024 && !value.contains("\r") && !value.contains("\n") ? value : nil
      }
      return .init(url: url, userAgent: userAgent)
    }
    let storyboard = formats.filter { $0.ext == "mhtml" }.sorted {
      ($0.width ?? 0) > ($1.width ?? 0)
    }.compactMap(\.storyboard).first
    return TimelineMedia(
      playbackStreams: streams,
      videoURL: TimelineFormat.remoteURL(ordered(video).first?.url), storyboard: storyboard)
  }
}

struct TimelineFormat: Decodable {
  let url: String?
  let ext: String?
  let transport: String?
  let vcodec: String?
  let acodec: String?
  let height: Int?
  let width: Int?
  let fps: Double?
  let rows: Int?
  let columns: Int?
  let fragments: [Fragment]?
  let headers: [String: String]?

  struct Fragment: Decodable {
    let url: String?
    let duration: Double?
  }
  enum CodingKeys: String, CodingKey {
    case url, ext, vcodec, acodec, height, width, fps, rows, columns, fragments
    case transport = "protocol"
    case headers = "http_headers"
  }

  static func remoteURL(_ text: String?) -> URL? {
    guard let text, let url = URL(string: text),
      ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
      url.host != nil, url.user == nil, url.password == nil
    else { return nil }
    return url
  }

  var storyboard: TimelineMedia.Storyboard? {
    guard let columns, let rows, (1...100).contains(columns), (1...100).contains(rows),
      let fps, fps.isFinite, fps > 0, fps <= 60,
      let fragments, !fragments.isEmpty, fragments.count <= 10_000
    else { return nil }
    var start = 0.0
    var sheets: [TimelineMedia.Storyboard.Sheet] = []
    for fragment in fragments {
      guard let url = Self.remoteURL(fragment.url), let duration = fragment.duration,
        duration.isFinite, duration > 0, (start + duration).isFinite
      else { return nil }
      sheets.append(.init(url: url, start: start, duration: duration))
      start += duration
    }
    return .init(columns: columns, rows: rows, framesPerSecond: fps, sheets: sheets)
  }
}
