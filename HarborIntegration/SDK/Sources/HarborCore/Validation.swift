import Foundation
import CryptoKit
import HarborKit

public struct HarborError: LocalizedError, Equatable {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}
public enum Versions {
    public static func parts(_ value: String) throws -> [Int] {
        let pieces = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !pieces.isEmpty, pieces.count <= 4, value.count <= 40,
              pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) && Int($0) != nil }) else {
            throw HarborError("Version must contain one to four numeric components: \(value)")
        }
        return pieces.map { Int($0)! }
    }
    public static func compare(_ a: String, _ b: String) throws -> ComparisonResult {
        let x = try parts(a), y = try parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l < r { return .orderedAscending }; if l > r { return .orderedDescending }
        }
        return .orderedSame
    }
    public static var currentOS: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}
public enum Digests {
    public static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    public static func sha256(file: URL, cancellation: () throws -> Void = {}) throws -> String {
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        var h = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { try cancellation(); h.update(data: data) }
        return h.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
public enum CatalogVerifier {
    public static let maxBytes = 2_097_152
    public static func validateSource(_ source: PublisherSource) throws {
        try secureURL(source.url)
        guard source.publicKey.count == 32, !source.keyID.isEmpty, source.keyID.count <= 80 else { throw HarborError("Enter a 32-byte Ed25519 public key and a key identifier.") }
        _ = try Curve25519.Signing.PublicKey(rawRepresentation: source.publicKey)
    }
    public static func secureURL(_ url: URL) throws {
        guard url.scheme == "https", let host = url.host, !host.isEmpty, url.user == nil, url.password == nil, url.fragment == nil else {
            throw HarborError("Release sources and downloads must use HTTPS without embedded credentials or fragments.")
        }
    }
    public static func verify(_ data: Data, source: PublisherSource, minimumSequence: Int64 = 0, previousDigest: String? = nil, now: Date = Date()) throws -> Catalog {
        try validateSource(source)
        guard data.count <= maxBytes else { throw HarborError("The catalog is too large.") }
        let envelope = try ContractJSON.decoder().decode(SignedCatalog.self, from: data)
        guard envelope.keyID == source.keyID, envelope.signature.count == 64,
              try Curve25519.Signing.PublicKey(rawRepresentation: source.publicKey).isValidSignature(envelope.signature, for: envelope.payload) else {
            throw HarborError("Catalog authentication failed. Keep the existing apps and contact the publisher.")
        }
        let catalog = try ContractJSON.decoder().decode(Catalog.self, from: envelope.payload)
        guard catalog.schema == 1, catalog.sequence > 0, catalog.sequence >= minimumSequence,
              catalog.issuedAt <= now.addingTimeInterval(300), catalog.expiresAt > now,
              catalog.expiresAt > catalog.issuedAt, catalog.expiresAt.timeIntervalSince(catalog.issuedAt) <= 31 * 86400 else {
            throw HarborError("This catalog is expired, rolled back, or uses an unsupported format. Refresh from the publisher.")
        }
        if catalog.sequence == minimumSequence, let previousDigest, Digests.sha256(envelope.payload) != previousDigest {
            throw HarborError("The publisher reused a catalog sequence with different contents.")
        }
        guard catalog.releases.count <= OwnedApps.all.count, Set(catalog.releases.map(\.appID)).count == catalog.releases.count else {
            throw HarborError("The catalog contains duplicate or excessive app releases.")
        }
        for release in catalog.releases { try validateRelease(release) }
        return catalog
    }
    public static func validateRelease(_ r: Release) throws {
        guard let app = OwnedApps.all.first(where: { $0.id == r.appID }), r.architecture == "arm64",
              r.bytes > 0, r.bytes <= 4_294_967_296, r.sha256.count == 64,
              r.sha256.allSatisfy({ "0123456789abcdef".contains($0) }), r.notes.count <= 16000,
              r.url.pathExtension.lowercased() == "zip" else { throw HarborError("The release identity, architecture, size or archive format is unsupported.") }
        try secureURL(r.url)
        _ = try Versions.parts(r.version); _ = try Versions.parts(r.build)
        guard try Versions.compare(r.minimumOS, app.minimumOS) != .orderedAscending else { throw HarborError("Release requires an invalid minimum macOS version.") }
        if r.channel == .preview, !r.url.lastPathComponent.hasSuffix("-unnotarized.zip") {
            throw HarborError("Preview artifact filenames must end with -unnotarized.zip.")
        }
        if r.channel == .verified {
            guard let team = r.teamIdentifier, team.count == 10, team.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) else {
                throw HarborError("A verified release must name its Apple Developer Team.")
            }
        }
        if let signature = r.sparkleSignature, Data(base64Encoded: signature)?.count != 64 { throw HarborError("Invalid Sparkle signature.") }
    }
}
