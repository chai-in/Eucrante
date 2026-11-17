import XCTest

@testable import EucranteCore

final class TimelineMediaTests: XCTestCase {
  func testCombinedMP4WithoutCodecLabelsIsAvailableForPlayback() throws {
    let formats = try decode(
      """
      [{"url":"https://example.com/480.mp4","ext":"mp4","protocol":"https","height":480},
       {"url":"https://example.com/1080.mp4","ext":"mp4","protocol":"https","height":1080}]
      """)
    let result = LocalMediaAcquirer.timelineSelection(formats, audioOnly: false)
    XCTAssertEqual(result.playbackURL?.lastPathComponent, "480.mp4")
  }

  func testStoryboardBoundaryMappingAndUnsafeURLs() throws {
    let formats = try decode(
      """
      [{"ext":"mhtml","width":160,"rows":2,"columns":3,"fps":0.5,
        "fragments":[{"url":"https://example.com/0.jpg","duration":12},
                     {"url":"https://example.com/1.jpg","duration":12}]},
       {"url":"file:///etc/passwd","ext":"mp4","protocol":"http","height":360}]
      """)
    let result = LocalMediaAcquirer.timelineSelection(formats, audioOnly: false)
    XCTAssertNil(result.playbackURL)
    let board = try XCTUnwrap(result.storyboard)
    XCTAssertEqual(board.frame(at: 0)?.column, 0)
    XCTAssertEqual(board.frame(at: 10)?.row, 1)
    XCTAssertEqual(board.frame(at: 10)?.column, 2)
    XCTAssertEqual(board.frame(at: 12)?.sheet, 1)
    XCTAssertEqual(board.frame(at: 12)?.column, 0)
    XCTAssertNil(board.frame(at: .nan))
    XCTAssertNil(TimelineFormat.remoteURL("https://user:password@example.com/video"))
  }

  func testLastPartialStoryboardSheetDoesNotShowEmptyCellsAtEnd() throws {
    let formats = try decode(
      """
      [{"ext":"mhtml","width":160,"rows":2,"columns":3,"fps":0.5,
        "fragments":[{"url":"https://example.com/last.jpg","duration":4}]}]
      """)
    let board = try XCTUnwrap(
      LocalMediaAcquirer.timelineSelection(formats, audioOnly: false).storyboard)
    XCTAssertEqual(board.frame(at: 4)?.column, 1)
    XCTAssertEqual(board.frame(at: 4)?.row, 0)
  }

  func testAudioOnlyStreamAndVideoOnlyAreNotConfusedWithCombinedPlayback() throws {
    let formats = try decode(
      """
      [{"url":"https://example.com/video.mp4","ext":"mp4","protocol":"https",
        "height":360,"vcodec":"avc1","acodec":"none"},
       {"url":"https://example.com/audio.m4a","ext":"m4a","protocol":"https",
        "vcodec":"none","acodec":"mp4a"}]
      """)
    XCTAssertNil(LocalMediaAcquirer.timelineSelection(formats, audioOnly: false).playbackURL)
    XCTAssertNotNil(LocalMediaAcquirer.timelineSelection(formats, audioOnly: false).videoURL)
    XCTAssertEqual(
      LocalMediaAcquirer.timelineSelection(formats, audioOnly: true).playbackURL?.lastPathComponent,
      "audio.m4a")
  }

  private func decode(_ text: String) throws -> [TimelineFormat] {
    try JSONDecoder().decode([TimelineFormat].self, from: Data(text.utf8))
  }
}
