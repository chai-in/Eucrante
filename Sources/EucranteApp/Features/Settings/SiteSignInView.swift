import EucranteCore
import SwiftUI
@preconcurrency import WebKit

struct SiteSignInView: View {
  @ObservedObject var model: AppModel
  @State private var address = ""
  @State private var failure: String?
  @State private var loading = false

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 3) {
          Text("\(model.currentSite.name) website session").font(.headline)
          Text("Sign in on the website, then choose Done to recheck affected links.")
            .font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Button("Open Passwords") { model.openPasswordsApp() }
        Button("Done & Recheck") { model.finishSiteSignIn() }
          .keyboardShortcut(.defaultAction)
      }.padding(14)
      HStack {
        Image(systemName: "lock.shield")
        Text(address.isEmpty ? model.currentSite.signInURL.absoluteString : address)
          .font(.callout.monospaced()).lineLimit(1).textSelection(.enabled)
        Spacer()
        if loading { ProgressView().controlSize(.small) }
      }.padding(.horizontal, 14).padding(.bottom, 10)
      if let failure {
        Text(failure).font(.callout).foregroundStyle(.orange).padding(10)
      }
      Divider()
      if let store = model.siteWebsiteDataStore {
        SiteWebView(
          dataStore: store, initialURL: model.currentSite.signInURL,
          address: $address, failure: $failure, loading: $loading)
      } else {
        ContentUnavailableView("Website browser unavailable in this preview", systemImage: "globe")
      }
    }.frame(minWidth: 840, minHeight: 620)
  }
}

private struct SiteWebView: NSViewRepresentable {
  let dataStore: WKWebsiteDataStore
  let initialURL: URL
  @Binding var address: String
  @Binding var failure: String?
  @Binding var loading: Bool
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = dataStore
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.navigationDelegate = context.coordinator
    view.uiDelegate = context.coordinator
    view.allowsMagnification = true
    view.allowsBackForwardNavigationGestures = true
    view.load(URLRequest(url: initialURL))
    return view
  }
  func updateNSView(_ view: WKWebView, context: Context) { context.coordinator.parent = self }

  @MainActor
  final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    var parent: SiteWebView
    init(_ parent: SiteWebView) { self.parent = parent }
    func webView(_ view: WKWebView, decidePolicyFor action: WKNavigationAction) async
      -> WKNavigationActionPolicy
    {
      guard let url = action.request.url, SiteNavigationPolicy.allows(url) else {
        parent.failure =
          "This navigation was blocked. Website sign-in requires a secure HTTPS page."
        return .cancel
      }
      if action.targetFrame?.isMainFrame == true {
        // Show the actual destination, including third-party identity providers.
        parent.address = url.absoluteString
      }
      return .allow
    }
    func webView(
      _ view: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
      for action: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
      if action.targetFrame == nil, let url = action.request.url, SiteNavigationPolicy.allows(url) {
        view.load(action.request)
      }
      return nil
    }
    func webView(_ view: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
      parent.loading = true
      parent.failure = nil
    }
    func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) {
      parent.loading = false
      parent.address = view.url?.absoluteString ?? parent.address
    }
    func webView(
      _ view: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
      withError error: Error
    ) {
      parent.loading = false
      if (error as NSError).code != NSURLErrorCancelled {
        parent.failure = error.localizedDescription
      }
    }
    func webView(_ view: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
      parent.loading = false
      parent.failure = error.localizedDescription
    }
  }
}

enum SiteNavigationPolicy {
  static func allows(_ url: URL) -> Bool {
    if url.absoluteString == "about:blank" { return true }
    return url.scheme == "https" && url.host != nil && url.user == nil && url.password == nil
  }
}
