import Foundation
import HarborKit

public struct TrustWatermark: Codable, Sendable { public let sequence: Int64; public let digest: String }
public struct Preferences: Codable, Sendable {
    public var source: PublisherSource?
    public var watermarks: [String: TrustWatermark] = [:]
    public var setupNotes: [String: String] = [:]
    public init() {}
}
public final class CatalogStore: @unchecked Sendable {
    public let directory: URL
    public private(set) var preferences: Preferences
    public init(directory: URL) throws {
        self.directory = directory
        try SafeFiles.ensureDirectory(directory, privateMode: true)
        let url = directory.appendingPathComponent("preferences.json")
        preferences = SafeFiles.exists(url) ? try ContractJSON.decoder().decode(Preferences.self, from: SafeFiles.read(url, maxBytes: 1_048_576)) : Preferences()
    }
    public func setSource(_ source: PublisherSource) throws {
        try CatalogVerifier.validateSource(source)
        var next = preferences; next.source = source
        try save(next)
    }
    public func setSetupNote(app: String, kind: String, note: String) throws {
        var next = preferences; next.setupNotes["\(app).\(kind)"] = note; try save(next)
    }
    public func cachedCatalog(now: Date = Date()) throws -> Catalog? {
        guard let source = preferences.source else { return nil }
        let file = directory.appendingPathComponent("catalog.json")
        guard SafeFiles.exists(file) else { return nil }
        return try verify(SafeFiles.read(file, maxBytes: Int64(CatalogVerifier.maxBytes)), source: source, now: now)
    }
    public func accept(_ data: Data, source: PublisherSource, now: Date = Date()) throws -> Catalog {
        guard source == preferences.source else { throw HarborError("The publisher changed during this request. Refresh again.") }
        let catalog = try verify(data, source: source, now: now)
        let envelope = try ContractJSON.decoder().decode(SignedCatalog.self, from: data)
        var next = preferences
        next.watermarks[Digests.sha256(source.publicKey)] = .init(sequence: catalog.sequence, digest: Digests.sha256(envelope.payload))
        // Persist the anti-rollback watermark first. A crash between writes fails closed on the older cache.
        try save(next)
        try SafeFiles.atomicWrite(data, to: directory.appendingPathComponent("catalog.json"))
        return catalog
    }
    private func verify(_ data: Data, source: PublisherSource, now: Date) throws -> Catalog {
        let watermark = preferences.watermarks[Digests.sha256(source.publicKey)]
        return try CatalogVerifier.verify(data, source: source, minimumSequence: watermark?.sequence ?? 0, previousDigest: watermark?.digest, now: now)
    }
    private func save(_ next: Preferences) throws {
        try SafeFiles.atomicWrite(ContractJSON.encoder().encode(next), to: directory.appendingPathComponent("preferences.json"))
        preferences = next
    }
}
public struct PreparedRelease: Sendable {
    public let appURL: URL
    public let archiveURL: URL
    public let facts: BundleFacts
}
public enum ReleasePreparation {
    public static func prepare(_ release: Release, in directory: URL, cancellation: Cancellation,
                               progress: @escaping @Sendable (String, Double) -> Void) async throws -> PreparedRelease {
        try CatalogVerifier.validateRelease(release)
        guard try Versions.compare(release.minimumOS, Versions.currentOS) != .orderedDescending else { throw HarborError("This release requires macOS \(release.minimumOS).") }
        guard let app = OwnedApps.all.first(where: { $0.id == release.appID }) else { throw HarborError("Unknown application.") }
        try SafeFiles.ensureDirectory(directory, privateMode: true)
        let archive = directory.appendingPathComponent("release.zip")
        progress("Downloading authenticated release", 0)
        _ = try await Download().fetch(release.url, to: archive, limit: release.bytes, exact: release.bytes) { progress("Downloading authenticated release", $0 * 0.55) }
        try cancellation.check(); progress("Verifying archive", 0.58)
        try validateArchive(archive, release: release, cancellation: cancellation)
        try SafeFiles.quarantine(archive)
        let bundle = try ArchiveExtractor.extract(archive, to: directory.appendingPathComponent("expanded"), bundleName: app.bundleName, cancellation: cancellation)
        try SafeFiles.quarantine(bundle)
        progress("Verifying app identity and signing", 0.8)
        let facts = try BundleInspector.inspect(bundle, app: app, release: release, cancellation: cancellation)
        return .init(appURL: bundle, archiveURL: archive, facts: facts)
    }
    public static func validateArchive(_ url: URL, release: Release, cancellation: Cancellation = Cancellation()) throws {
        guard try SafeFiles.regularFile(url, maxBytes: release.bytes) == release.bytes,
              try Digests.sha256(file: url, cancellation: cancellation.check) == release.sha256 else { throw HarborError("The artifact does not match the authenticated catalog. Nothing was installed.") }
    }
}
