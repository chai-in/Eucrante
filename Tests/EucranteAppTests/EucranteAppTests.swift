import XCTest

@testable import EucranteApp

final class EucranteAppTests: XCTestCase {
  func testYouTubeRecognitionRejectsLookalikeHosts() throws {
    XCTAssertTrue(AppModel.isYouTube(try XCTUnwrap(URL(string: "https://youtube.com/watch?v=1"))))
    XCTAssertTrue(
      AppModel.isYouTube(try XCTUnwrap(URL(string: "https://www.youtube.com/watch?v=1"))))
    XCTAssertTrue(AppModel.isYouTube(try XCTUnwrap(URL(string: "https://youtu.be/example"))))
    XCTAssertFalse(AppModel.isYouTube(try XCTUnwrap(URL(string: "https://youtube.com.evil.test"))))
    XCTAssertFalse(AppModel.isYouTube(try XCTUnwrap(URL(string: "https://notyoutube.com"))))
  }

  func testEmbeddedSignInNavigationAllowsOnlyRequiredHTTPSDomains() throws {
    let allowed = [
      "https://youtube.com/account",
      "https://accounts.google.com/signin",
      "https://www.gstatic.com/example",
      "https://lh3.googleusercontent.com/example",
      "https://youtube.googleapis.com/example",
      "about:blank",
    ]
    for value in allowed {
      XCTAssertTrue(
        YouTubeNavigationPolicy.allows(try XCTUnwrap(URL(string: value))),
        value
      )
    }

    let blocked = [
      "http://youtube.com/account",
      "https://youtube.com.evil.test/account",
      "https://google.com.evil.test/signin",
      "https://example.com/",
      "file:///tmp/example",
      "data:text/html,example",
    ]
    for value in blocked {
      XCTAssertFalse(
        YouTubeNavigationPolicy.allows(try XCTUnwrap(URL(string: value))),
        value
      )
    }
  }
}
