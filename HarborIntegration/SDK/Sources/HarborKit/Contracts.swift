import Foundation

/// App-owned identity and setup guidance. No version here implies a published release.
public struct AppDefinition: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let bundleIdentifier: String
    public let bundleName: String
    public let summary: String
    public let symbol: String
    public let minimumOS: String
    public let permissions: [PermissionGuide]
    public init(id: String, name: String, bundleIdentifier: String, bundleName: String, summary: String, symbol: String,
                minimumOS: String, permissions: [PermissionGuide]) {
        self.id = id; self.name = name; self.bundleIdentifier = bundleIdentifier; self.bundleName = bundleName
        self.summary = summary; self.symbol = symbol; self.minimumOS = minimumOS; self.permissions = permissions
    }
}

public struct PermissionGuide: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case fullDiskAccess, photos, automation, notifications, files }
    public let kind: Kind
    public let title: String
    public let reason: String
    public let steps: String
    public let limitedAccess: String
    public var id: String { kind.rawValue }
    public init(kind: Kind, title: String, reason: String, steps: String, limitedAccess: String) {
        self.kind = kind; self.title = title; self.reason = reason; self.steps = steps; self.limitedAccess = limitedAccess
    }
    /// These links are navigation only. They neither request nor grant another app's TCC permissions.
    public var settingsURL: URL? {
        let pane: String
        switch kind {
        case .fullDiskAccess: pane = "Privacy_AllFiles"
        case .photos: pane = "Privacy_Photos"
        case .automation: pane = "Privacy_Automation"
        case .notifications: return URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        case .files: pane = "Privacy_FilesAndFolders"
        }
        return URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(pane)")
    }
    public var externalStatus: String {
        kind == .files ? "Chosen inside the app" : "macOS does not expose this app's status to Harbor"
    }
}

/// Immutable known identities; old bundle IDs and preview IDs never silently migrate production data.
public enum OwnedApps {
    public static let all: [AppDefinition] = [
        .init(id: "eucrante", name: "Eucrante", bundleIdentifier: "app.eucrante.client", bundleName: "Eucrante.app",
              summary: "Save media and make it your own.", symbol: "arrow.down.circle", minimumOS: "14.0", permissions: [
                .init(kind: .files, title: "Save location", reason: "Choose where finished downloads are saved.",
                      steps: "Open Eucrante and choose a destination folder in Settings. Use the system folder picker.", limitedAccess: "Use a folder you can already access."),
                .init(kind: .notifications, title: "Download notifications", reason: "Optional alerts when a download finishes.",
                      steps: "Enable completion notifications in Eucrante. Approve its own macOS prompt, or adjust Eucrante in Notifications settings.", limitedAccess: "Follow download progress in Eucrante without notifications."),
                .init(kind: .automation, title: "Import to Music", reason: "Optional permission to send a finished audio file to Music.",
                      steps: "Choose Import to Music for a finished file in Eucrante. Approve the prompt for Eucrante controlling Music.", limitedAccess: "Save audio to a folder and import it yourself.")]),
        .init(id: "melodex", name: "Melodex", bundleIdentifier: "app.melodex.client", bundleName: "Melodex.app",
              summary: "Your music library, connected and local.", symbol: "music.note.list", minimumOS: "14.0", permissions: [
                .init(kind: .automation, title: "Read the Music library", reason: "Read your library and playlists from the Music app.",
                      steps: "Open Melodex, connect the local Music app, and start an import. Approve the Automation prompt for Melodex controlling Music.", limitedAccess: "Import supported files and manage local library data without Music access."),
                .init(kind: .files, title: "Imports and backups", reason: "Select the files or folders you want Melodex to use.",
                      steps: "Use Melodex's Import or Backup controls and the macOS file picker.", limitedAccess: "Your existing local library stays available. iCloud sync separately requires an Apple-signed build and your iCloud account.")]),
        .init(id: "aegle", name: "Aegle", bundleIdentifier: "com.chai.Aegle", bundleName: "Aegle.app",
              summary: "Explore and care for your photo library.", symbol: "photo.on.rectangle.angled", minimumOS: "15.0", permissions: [
                .init(kind: .photos, title: "Photo library", reason: "Browse and analyze photos locally. Changes remain actions you choose in Aegle.",
                      steps: "Open Aegle and use its library access button. Aegle requests Photos access and can re-check its own status. If denied, enable Aegle in Photos settings and return to it.", limitedAccess: "Keep access off and use Aegle's onboarding. Real-library browsing requires Photos access; only the photos macOS makes available can be used.")]),
        .init(id: "mactidy", name: "Mac Tidy", bundleIdentifier: "com.chai.mactidy", bundleName: "Mac Tidy.app",
              summary: "Understand your storage. Clean with care.", symbol: "externaldrive", minimumOS: "14.0", permissions: [
                .init(kind: .fullDiskAccess, title: "Full Disk Access", reason: "Optional for complete scans of protected caches, logs and application data.",
                      steps: "Open Full Disk Access settings. Enable Mac Tidy. If missing, click + and choose the exact installed app shown below. Quit and reopen Mac Tidy after changing access.", limitedAccess: "Continue with limited access. Mac Tidy can scan accessible locations and must skip protected files."),
                .init(kind: .automation, title: "Finder and selected apps", reason: "Reveal or move selected files, or ask an app to quit during an uninstall you choose.",
                      steps: "Use the relevant action in Mac Tidy. Approve its own Automation prompt only for the app you expect.", limitedAccess: "Use Finder yourself and quit selected apps manually.")]),
        .init(id: "harbor", name: "Harbor", bundleIdentifier: "com.chai.harbor", bundleName: "Harbor.app",
              summary: "One home for your Mac apps.", symbol: "shippingbox", minimumOS: "14.0", permissions: [])
    ]
}

public enum ReleaseChannel: String, Codable, Sendable { case verified, preview }
public struct Release: Codable, Equatable, Sendable {
    public let appID: String
    public let version: String
    public let build: String
    public let minimumOS: String
    public let architecture: String
    public let url: URL
    public let bytes: Int64
    public let sha256: String
    public let channel: ReleaseChannel
    public let teamIdentifier: String?
    public let notes: String
    public let sparkleSignature: String?
    public init(appID: String, version: String, build: String, minimumOS: String, architecture: String = "arm64", url: URL,
                bytes: Int64, sha256: String, channel: ReleaseChannel, teamIdentifier: String?, notes: String = "", sparkleSignature: String? = nil) {
        self.appID = appID; self.version = version; self.build = build; self.minimumOS = minimumOS; self.architecture = architecture
        self.url = url; self.bytes = bytes; self.sha256 = sha256; self.channel = channel; self.teamIdentifier = teamIdentifier
        self.notes = notes; self.sparkleSignature = sparkleSignature
    }
}
public struct Catalog: Codable, Sendable {
    public let schema: Int
    public let sequence: Int64
    public let issuedAt: Date
    public let expiresAt: Date
    public let releases: [Release]
    public init(sequence: Int64, issuedAt: Date, expiresAt: Date, releases: [Release]) {
        schema = 1; self.sequence = sequence; self.issuedAt = issuedAt; self.expiresAt = expiresAt; self.releases = releases
    }
}
/// Signature is over the exact decoded payload bytes, avoiding ambiguous JSON canonicalization.
public struct SignedCatalog: Codable {
    public let keyID: String
    public let payload: Data
    public let signature: Data
    public init(keyID: String, payload: Data, signature: Data) { self.keyID = keyID; self.payload = payload; self.signature = signature }
}
public struct PublisherSource: Codable, Equatable, Sendable {
    public let url: URL
    public let keyID: String
    public let publicKey: Data
    public init(url: URL, keyID: String, publicKey: Data) { self.url = url; self.keyID = keyID; self.publicKey = publicKey }
}
public enum ContractJSON {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }
    public static func decoder() -> JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
