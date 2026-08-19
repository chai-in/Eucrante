import SwiftUI
@preconcurrency import WebKit

struct YouTubeSignInView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Text("YouTube")
          .font(.headline)
        Spacer()
        Button("Open Passwords") { model.openPasswordsApp() }
          .help("Open Apple Passwords, then copy and paste your Google login")
        Button("Done") { model.finishYouTubeSignIn() }
          .keyboardShortcut(.defaultAction)
      }
      .padding(.horizontal, 14)
      .frame(height: 46)

      Divider()
      YouTubeWebView()
    }
    .frame(minWidth: 840, minHeight: 620)
  }
}

private struct YouTubeWebView: NSViewRepresentable {
  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .default()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = context.coordinator
    webView.allowsMagnification = true
    if let url = URL(string: "https://www.youtube.com/account") {
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
      if url.scheme == "about" {
        return .allow
      }
      guard url.scheme == "https", let host = url.host?.lowercased() else {
        return .cancel
      }
      let allowedDomains = [
        "youtube.com", "google.com", "gstatic.com", "googleusercontent.com", "googleapis.com",
      ]
      let allowed = allowedDomains.contains { host == $0 || host.hasSuffix(".\($0)") }
      return allowed ? .allow : .cancel
    }
  }
}
