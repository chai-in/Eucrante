import AppKit
import SwiftUI

public struct HarborRoute: Equatable, Sendable {
    public enum Destination: String, Sendable { case updates, setup }
    public let appID: String
    public let destination: Destination
    public init(appID: String, destination: Destination) {
        self.appID = appID; self.destination = destination
    }
    public var url: URL? {
        guard OwnedApps.all.contains(where: { $0.id == appID }) else { return nil }
        var c = URLComponents(); c.scheme = "harbor"; c.host = "app"; c.path = "/" + appID
        c.queryItems = [.init(name: "view", value: destination.rawValue)]
        return c.url
    }
    /// Navigation only: links cannot authorize an install, change trust, or grant a permission.
    public static func parse(_ url: URL) -> HarborRoute? {
        guard url.absoluteString.utf8.count <= 512, let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme == "harbor", c.host == "app", c.user == nil, c.password == nil, c.port == nil, c.fragment == nil,
              c.queryItems?.count == 1, c.queryItems?.first?.name == "view",
              let destination = Destination(rawValue: c.queryItems?.first?.value ?? ""),
              let app = OwnedApps.all.first(where: { c.percentEncodedPath == "/" + $0.id }) else { return nil }
        return .init(appID: app.id, destination: destination)
    }
}

/// A host app uses Harbor for updates; TCC requests and app data stay with that host app.
@MainActor public enum HarborClient {
    public static func open(appID: String, destination: HarborRoute.Destination) {
        guard let route = HarborRoute(appID: appID, destination: destination).url else { return }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.chai.harbor").first?.bundleURL
        guard let harbor = running ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.chai.harbor"),
              Bundle(url: harbor)?.bundleIdentifier == "com.chai.harbor" else {
            let alert = NSAlert()
            alert.messageText = "Harbor isn’t installed"
            alert.informativeText = "Install Harbor.app, open it once, then use this command again. Harbor keeps app updates in one place. You can continue using this app and its own permission controls."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([route], withApplicationAt: harbor, configuration: configuration) { _, error in
            guard let error else { return }
            Task { @MainActor in
                let alert = NSAlert(); alert.messageText = "Couldn’t open Harbor"
                alert.informativeText = error.localizedDescription; alert.runModal()
            }
        }
    }
}

public struct HarborCommands: Commands {
    private let appID: String
    public init(appID: String) { self.appID = appID }
    public var body: some Commands {
        CommandGroup(after: .appInfo) {
            Divider()
            Button("Check for Updates with Harbor…") { HarborClient.open(appID: appID, destination: .updates) }
            Button("Permissions & Setup in Harbor…") { HarborClient.open(appID: appID, destination: .setup) }
        }
    }
}
