import Foundation
import Security
import CryptoKit
import HarborCore
import HarborKit

func writeNew(_ data: Data, _ path: String) throws {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    try SafeFiles.noSymlinkAncestors(url.deletingLastPathComponent())
    guard !SafeFiles.exists(url) else { throw HarborError("Refusing to overwrite \(path). Choose a new output path.") }
    try data.write(to: url, options: .withoutOverwriting)
}
func keyQuery(_ id: String) throws -> [String: Any] {
    guard !id.isEmpty, id.count <= 80 else { throw HarborError("Key identifiers must contain 1–80 characters.") }
    return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.chai.harbor.release-signing", kSecAttrAccount as String: id]
}
func privateKey(_ id: String) throws -> Curve25519.Signing.PrivateKey {
    var query = try keyQuery(id); query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let bytes = result as? Data else { throw HarborError("Cannot read signing key \(id) from Keychain (\(status)).") }
    return try Curve25519.Signing.PrivateKey(rawRepresentation: bytes)
}
func app(_ id: String) throws -> AppDefinition {
    guard let app = OwnedApps.all.first(where: { $0.id == id }) else { throw HarborError("Unknown app ID. Choose eucrante, melodex, aegle, mactidy or harbor.") }; return app
}
func readRelease(_ path: String) throws -> Release { try ContractJSON.decoder().decode(Release.self, from: SafeFiles.read(URL(fileURLWithPath: path), maxBytes: 1_048_576)) }
func xml(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
}
let usage = """
Harbor publisher tools — all output is local; nothing is uploaded.

  list
  manifest APP-ID OUTPUT.json
  check-integration APP-ID APP.app
  sign-stdin KEY-ID CATALOG.json SIGNED-CATALOG.json  Reads a base64 Ed25519 seed from stdin (CI only)
  inspect APP-ID APP.app
  package APP-ID APP.app OUTPUT-DIRECTORY HTTPS-ZIP-URL preview|verified
  keygen KEY-ID PUBLIC-KEY.json                  Creates a Keychain key; prints no private material
  public-key KEY-ID PUBLIC-KEY.json
  catalog SEQUENCE DAYS OUTPUT.json RELEASE.json...
  sign KEY-ID CATALOG.json SIGNED-CATALOG.json
  verify SOURCE.json SIGNED-CATALOG.json
  attach-sparkle RELEASE.json ED25519-SIGNATURE OUTPUT.json
  appcast HARBOR-RELEASE.json OUTPUT.xml         Then sign the XML with Sparkle's sign_update tool

PublisherSource JSON: {"url":"your actual HTTPS catalog URL","keyID":"your key ID","publicKey":"base64 public key"}
Verified packages require Developer ID and notarization. Preview packages remain explicitly unnotarized.
"""
do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else { print(usage); exit(0) }
    switch command {
    case "list":
        for a in OwnedApps.all { print("\(a.id)\t\(a.name)\t\(a.bundleIdentifier)\tmacOS \(a.minimumOS)+") }
    case "manifest":
        guard args.count == 3 else { throw HarborError(usage) }
        try writeNew(ContractJSON.encoder().encode(IntegrationManifest(app: app(args[1]))), args[2])
    case "check-integration":
        guard args.count == 3 else { throw HarborError(usage) }
        let definition = try app(args[1]), bundle = URL(fileURLWithPath: args[2])
        let manifestURL = bundle.appendingPathComponent("Contents/Resources/" + IntegrationManifest.resourceName)
        let manifest = try ContractJSON.decoder().decode(IntegrationManifest.self, from: SafeFiles.read(manifestURL, maxBytes: 65536))
        guard manifest.matches(definition) else { throw HarborError("The embedded Harbor integration has an unexpected app identity.") }
        _ = try BundleInspector.inspect(bundle, app: definition)
        print("Harbor integration and bundle validated for \(definition.name).")
    case "inspect":
        guard args.count == 3 else { throw HarborError(usage) }
        let f = try BundleInspector.inspect(URL(fileURLWithPath: args[2]).standardizedFileURL, app: app(args[1]))
        print("\(f.identifier) · \(f.version) (\(f.build)) · arm64 · macOS \(f.minimumOS)+\n\(f.signature)")
    case "package":
        guard args.count == 6, let channel = ReleaseChannel(rawValue: args[5]), let remote = URL(string: args[4]) else { throw HarborError(usage) }
        let definition = try app(args[1]); try CatalogVerifier.secureURL(remote)
        let source = URL(fileURLWithPath: args[2]).standardizedFileURL
        let output = URL(fileURLWithPath: args[3]).standardizedFileURL
        try SafeFiles.ensureDirectory(output)
        let scratch = output.appendingPathComponent(".harbor-package-\(UUID().uuidString)")
        try SafeFiles.ensureDirectory(scratch, privateMode: true); defer { try? SafeFiles.fm.removeItem(at: scratch) }
        try SafeFiles.noSymlinkAncestors(source); try BundleInspector.validateTree(source)
        let snapshot = scratch.appendingPathComponent(definition.bundleName)
        try SafeFiles.fm.copyItem(at: source, to: snapshot)
        let facts = try BundleInspector.inspect(snapshot, app: definition)
        let filename = "\(definition.id)-\(facts.version)-\(facts.build)-arm64\(channel == .preview ? "-unnotarized" : "").zip"
        guard remote.lastPathComponent == filename else { throw HarborError("The URL must end in the exact artifact filename: \(filename)") }
        let archive = scratch.appendingPathComponent(filename)
        let result = try SystemProcess.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", "--norsrc", "--noextattr", snapshot.path, archive.path], timeout: 600)
        guard result.status == 0 else { throw HarborError(result.text) }
        let size = try SafeFiles.regularFile(archive, maxBytes: 4_294_967_296)
        let release = Release(appID: definition.id, version: facts.version, build: facts.build, minimumOS: facts.minimumOS,
                              url: remote, bytes: size, sha256: try Digests.sha256(file: archive), channel: channel, teamIdentifier: facts.teamIdentifier)
        try CatalogVerifier.validateRelease(release)
        let roundTrip = try ArchiveExtractor.extract(archive, to: scratch.appendingPathComponent("roundtrip"), bundleName: definition.bundleName)
        _ = try BundleInspector.inspect(roundTrip, app: definition, release: release)
        let metadata = output.appendingPathComponent(filename + ".release.json")
        guard !SafeFiles.exists(output.appendingPathComponent(filename)), !SafeFiles.exists(metadata) else { throw HarborError("Artifact output already exists.") }
        try SafeFiles.fm.moveItem(at: archive, to: output.appendingPathComponent(filename))
        try writeNew(ContractJSON.encoder().encode(release), metadata.path)
        print("Created and round-trip verified \(filename)\nRelease metadata: \(metadata.path)\nMetadata is not authenticated until included in a signed catalog.")
    case "keygen", "public-key":
        guard args.count == 3 else { throw HarborError(usage) }
        guard !SafeFiles.exists(URL(fileURLWithPath: args[2])) else { throw HarborError("Public-key output already exists.") }
        let key: Curve25519.Signing.PrivateKey
        if command == "keygen" {
            key = Curve25519.Signing.PrivateKey()
            var query = try keyQuery(args[1])
            query[kSecValueData as String] = key.rawRepresentation
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            query[kSecAttrSynchronizable as String] = false
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else { throw HarborError("Keychain refused key creation (\(status)); existing keys are never replaced.") }
        } else { key = try privateKey(args[1]) }
        let data = key.publicKey.rawRepresentation
        try writeNew(JSONSerialization.data(withJSONObject: ["keyID": args[1], "publicKey": data.base64EncodedString(), "fingerprint": Digests.sha256(data)], options: [.prettyPrinted, .sortedKeys]), args[2])
        print("Public key saved. Fingerprint: \(Digests.sha256(data))")
    case "catalog":
        guard args.count >= 4, let sequence = Int64(args[1]), sequence > 0, let days = Int(args[2]), (1...30).contains(days) else { throw HarborError(usage) }
        let releases = try args.dropFirst(4).map(readRelease)
        for release in releases { try CatalogVerifier.validateRelease(release) }
        guard Set(releases.map(\.appID)).count == releases.count else { throw HarborError("A catalog may include only one release per app.") }
        let now = Date()
        let catalog = Catalog(sequence: sequence, issuedAt: now, expiresAt: now.addingTimeInterval(Double(days) * 86400), releases: releases)
        try writeNew(ContractJSON.encoder().encode(catalog), args[3]); print("Created unsigned catalog. Review it before signing.")
    case "sign", "sign-stdin":
        guard args.count == 4 else { throw HarborError(usage) }
        let key: Curve25519.Signing.PrivateKey
        if command == "sign-stdin" {
            let bytes = try FileHandle.standardInput.read(upToCount: 128) ?? Data()
            guard bytes.count <= 96, let text = String(data: bytes, encoding: .utf8),
                  let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)), raw.count == 32 else {
                throw HarborError("Signing input must contain a single base64 Ed25519 seed. The input is never logged.")
            }
            key = try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
        } else { key = try privateKey(args[1]) }
        let payload = try SafeFiles.read(URL(fileURLWithPath: args[2]), maxBytes: 1_048_576)
        let envelope = SignedCatalog(keyID: args[1], payload: payload, signature: try key.signature(for: payload))
        let signed = try ContractJSON.encoder().encode(envelope)
        // This synthetic origin is used only for offline contract validation and is never published or contacted.
        let source = PublisherSource(url: URL(string: "https://localhost/catalog.json")!, keyID: args[1], publicKey: key.publicKey.rawRepresentation)
        _ = try CatalogVerifier.verify(signed, source: source)
        try writeNew(signed, args[3]); print("Catalog signed and verified locally. Nothing was published.")
    case "verify":
        guard args.count == 3 else { throw HarborError(usage) }
        let source = try ContractJSON.decoder().decode(PublisherSource.self, from: SafeFiles.read(URL(fileURLWithPath: args[1]), maxBytes: 65536))
        let catalog = try CatalogVerifier.verify(SafeFiles.read(URL(fileURLWithPath: args[2]), maxBytes: Int64(CatalogVerifier.maxBytes)), source: source)
        print("Authenticated catalog sequence \(catalog.sequence): \(catalog.releases.count) releases, expires \(catalog.expiresAt).")
    case "attach-sparkle":
        guard args.count == 4, Data(base64Encoded: args[2])?.count == 64 else { throw HarborError(usage) }
        let r = try readRelease(args[1])
        let signed = Release(appID: r.appID, version: r.version, build: r.build, minimumOS: r.minimumOS, url: r.url, bytes: r.bytes,
                             sha256: r.sha256, channel: r.channel, teamIdentifier: r.teamIdentifier, notes: r.notes, sparkleSignature: args[2])
        try writeNew(ContractJSON.encoder().encode(signed), args[3])
    case "appcast":
        guard args.count == 3 else { throw HarborError(usage) }
        let r = try readRelease(args[1]); try CatalogVerifier.validateRelease(r)
        guard r.appID == "harbor", r.channel == .verified, let signature = r.sparkleSignature else { throw HarborError("Harbor appcasts require a verified release with its Sparkle archive signature.") }
        let feed = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
        <channel><title>Harbor Updates</title><item><title>Harbor \(xml(r.version))</title>
        <sparkle:version>\(xml(r.build))</sparkle:version><sparkle:shortVersionString>\(xml(r.version))</sparkle:shortVersionString>
        <sparkle:minimumSystemVersion>\(xml(r.minimumOS))</sparkle:minimumSystemVersion>
        <description>\(xml(r.notes))</description>
        <enclosure url="\(xml(r.url.absoluteString))" length="\(r.bytes)" type="application/octet-stream" sparkle:edSignature="\(signature)" />
        </item></channel></rss>
        """
        try writeNew(Data(feed.utf8), args[2]); print("Created unsigned Sparkle feed. Sign this XML with Sparkle 2.9.6 sign_update before distribution.")
    #if DEBUG
    case "_test-crash":
        // Process-interruption fixture, omitted from distribution builds and confined to disposable test roots.
        guard args.count == 5, args[3].contains("/HarborTests-") else { throw HarborError("Invalid disposable crash fixture.") }
        let definition = try app(args[1]), root = URL(fileURLWithPath: args[3])
        let expected = try? InstalledApp.read(root.appendingPathComponent(definition.bundleName), app: definition)
        _ = try Installer(applications: root).install(source: URL(fileURLWithPath: args[2]), app: definition,
            release: nil, expected: expected, checkpoint: { point in if point.rawValue == args[4] { _exit(86) } })
        throw HarborError("The crash checkpoint was not reached.")
    #endif
    case "help", "--help", "-h": print(usage)
    default: throw HarborError(usage)
    }
} catch {
    FileHandle.standardError.write(Data(("Harbor: \(error.localizedDescription)\n").utf8)); exit(1)
}
