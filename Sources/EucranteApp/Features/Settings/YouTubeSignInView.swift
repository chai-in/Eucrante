import SwiftUI
@preconcurrency import WebKit

struct YouTubeSignInView: View {
  @ObservedObject var model: AppModel
  @State private var showingBrowser = false

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Text(browserIsVisible ? "Sign in to YouTube" : "YouTube is ready")
          .font(.headline)
        Spacer()
        if browserIsVisible {
          Button("Open Passwords") { model.openPasswordsApp() }
            .help("Copy your Google login from Apple Passwords")
        } else {
          Button("Use Another Account") { showingBrowser = true }
        }
        Button("Done") { model.finishYouTubeSignIn() }
          .keyboardShortcut(.defaultAction)
      }
      .padding(.horizontal, 14)
      .frame(height: 46)

      Divider()
      if browserIsVisible, let store = model.youtubeWebsiteDataStore {
        YouTubeWebView(dataStore: store)
      } else if browserIsVisible {
        ContentUnavailableView(
          "Sign-in unavailable in this preview", systemImage: "person.crop.circle")
      } else {
        ContentUnavailableView(
          "Connected",
          systemImage: "checkmark.circle.fill",
          description: Text("Your private YouTube session is connected.")
        )
      }
    }
    .frame(minWidth: 840, minHeight: 620)
  }

  private var browserIsVisible: Bool {
    !model.youtubeSessionReady || showingBrowser
  }
}

private struct YouTubeWebView: NSViewRepresentable {
  let dataStore: WKWebsiteDataStore
  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = dataStore
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = context.coordinator
    webView.allowsMagnification = true
    if let url = URL(
      string:
        "https://accounts.google.com/AccountChooser?service=youtube&continue=https%3A%2F%2Fwww.youtube.com%2Faccount"
    ) {
      webView.load(URLRequest(url: url))
    }
    return webView
  }

  func updateNSView(_ webView: WKWebView, context: Context) {}

  @MainActor
  final class Coordinator: NSObject, WKNavigationDelegate {
    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
      guard let url = navigationAction.request.url else {
        return .cancel
      }
      return YouTubeNavigationPolicy.allows(url) ? .allow : .cancel
    }
  }
}

enum YouTubeNavigationPolicy {
  static func allows(_ url: URL) -> Bool {
    if url.scheme == "about" { return true }
    guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
    let allowedDomains = [
      "youtube.com", "google.com", "gstatic.com", "googleusercontent.com", "googleapis.com",
    ]
    return allowedDomains.contains { host == $0 || host.hasSuffix(".\($0)") }
  }
}
