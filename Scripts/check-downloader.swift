import Foundation

// Used by the disposable HTTP fixture harness described in PERFORMANCE.md. The wrapper
// only supplies a local --load-info-json document; all extraction-format/output logic and
// HTTP transfers execute in the actual packaged yt-dlp helper.
@main
enum DownloaderCheck {
  static func main() async throws {
    let arguments = CommandLine.arguments
    let root = URL(fileURLWithPath: arguments[4], isDirectory: true)
    let acquirer = LocalMediaAcquirer(
      tools: .init(
        ytDLP: URL(fileURLWithPath: arguments[1]), deno: URL(fileURLWithPath: arguments[2]),
        ffmpeg: URL(fileURLWithPath: arguments[3])))
    let source = URL(string: "https://example.test/fixture")!
    let preview = try await acquirer.preview(
      sourceURL: source, cookieFile: nil, workingDirectory: root.appendingPathComponent("preview"))
    precondition(preview.metadata.title == "Local fixture" && preview.formats.count == 2)
    let acquired = try await acquirer.acquire(
      sourceURL: source, preset: .appleVideoBest, preferences: DownloadPreferences(),
      cookieFile: nil, workingDirectory: root.appendingPathComponent("acquisition"),
      progress: { _ in })
    guard case .merge(let video, let audio, _, let metadata) = acquired else {
      fatalError("Expected separate video and audio")
    }
    precondition(metadata.title == "Local fixture")
    let videoMatches =
      try Data(contentsOf: video) == Data(contentsOf: root.appendingPathComponent("video.mp4"))
    let audioMatches =
      try Data(contentsOf: audio) == Data(contentsOf: root.appendingPathComponent("audio.m4a"))
    precondition(videoMatches && audioMatches)
    print(
      "Packaged downloader preview and acquisition passed; both tracks match their source bytes.")
  }
}
