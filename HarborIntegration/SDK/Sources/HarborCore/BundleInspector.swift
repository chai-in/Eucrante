import Foundation
import Security
import HarborKit

public struct BundleFacts: Equatable, Sendable {
    public let identifier: String
    public let version: String
    public let build: String
    public let minimumOS: String
    public let teamIdentifier: String?
    public let signature: String
}
public enum BundleInspector {
    /// Inspection never launches an executable from the selected bundle.
    public static func inspect(_ url: URL, app: AppDefinition, release: Release? = nil, cancellation: Cancellation = Cancellation()) throws -> BundleFacts {
        try cancellation.check()
        try SafeFiles.noSymlinkAncestors(url)
        guard url.pathExtension == "app" else { throw HarborError("Choose an application bundle.") }
        try validateTree(url, cancellation: cancellation)
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        let data = try SafeFiles.read(infoURL, maxBytes: 1_048_576)
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let id = info["CFBundleIdentifier"] as? String, id == app.bundleIdentifier,
              info["CFBundlePackageType"] as? String == "APPL",
              let executable = info["CFBundleExecutable"] as? String,
              !executable.isEmpty, !executable.contains("/"), !executable.contains("\\"), executable != ".", executable != "..",
              let version = info["CFBundleShortVersionString"] as? String, let build = info["CFBundleVersion"] as? String,
              let minimumOS = info["LSMinimumSystemVersion"] as? String else { throw HarborError("This bundle does not match \(app.name)'s identity or is missing required metadata.") }
        _ = try Versions.parts(version); _ = try Versions.parts(build)
        guard try Versions.compare(minimumOS, Versions.currentOS) != .orderedDescending else { throw HarborError("\(app.name) needs macOS \(minimumOS) or later.") }
        let binary = url.appendingPathComponent("Contents/MacOS/\(executable)")
        _ = try SafeFiles.regularFile(binary, maxBytes: 4_294_967_296)
        guard SafeFiles.fm.isExecutableFile(atPath: binary.path), try inspectMachO(binary, declaredMinimum: minimumOS) else {
            throw HarborError("The app must have a native, Apple silicon-only arm64 executable.")
        }
        let enumerator = SafeFiles.fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey])!
        for case let file as URL in enumerator {
            try cancellation.check()
            if (try file.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
                // Header-based detection also covers dylibs and bundled command-line tools without executable extensions.
                _ = try inspectMachO(file, declaredMinimum: minimumOS)
            }
        }
        let manifestURL = url.appendingPathComponent("Contents/Resources/" + IntegrationManifest.resourceName)
        if SafeFiles.exists(manifestURL) {
            let manifest = try ContractJSON.decoder().decode(IntegrationManifest.self, from: SafeFiles.read(manifestURL, maxBytes: 65536))
            guard manifest.matches(app) else { throw HarborError("The embedded Harbor integration does not match the app identity.") }
        }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { throw HarborError("The app has no usable code signature.") }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess else { throw HarborError("The app's code signature is invalid or its contents were changed.") }
        var signing: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &signing) == errSecSuccess,
              let s = signing as? [String: Any], s[kSecCodeInfoIdentifier as String] as? String == app.bundleIdentifier else { throw HarborError("The signing identity does not match this app.") }
        let team = s[kSecCodeInfoTeamIdentifier as String] as? String
        if let release {
            guard version == release.version, build == release.build, minimumOS == release.minimumOS else { throw HarborError("The app's version or minimum macOS version disagrees with the authenticated release.") }
            if release.channel == .verified {
                guard team == release.teamIdentifier, let team else { throw HarborError("The app belongs to an unexpected Apple Developer Team.") }
                var requirement: SecRequirement?
                let expression = "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"\(team)\""
                guard SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess,
                      SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else { throw HarborError("This release needs a valid Developer ID Application signature.") }
                let assessment = try SystemProcess.run("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=4", url.path], cancellation: cancellation)
                guard assessment.status == 0, assessment.text.contains("source=Notarized Developer ID") else { throw HarborError("macOS did not accept this as a notarized Developer ID release. \(assessment.text.trimmingCharacters(in: .whitespacesAndNewlines))") }
                if let entitlements = s[kSecCodeInfoEntitlementsDict as String] as? [String: Any], entitlements["com.apple.security.get-task-allow"] as? Bool == true {
                    throw HarborError("A verified release must not allow debugger attachment.")
                }
            } else if let expected = release.teamIdentifier, expected != team { throw HarborError("The preview's signing team does not match its release metadata.") }
        }
        return .init(identifier: id, version: version, build: build, minimumOS: minimumOS, teamIdentifier: team,
                     signature: team.map { "Apple team \($0)" } ?? "Ad-hoc signature · publisher not authenticated")
    }

    public static func validateTree(_ root: URL, cancellation: Cancellation = Cancellation()) throws {
        let base = root.standardizedFileURL.path + "/"
        var count = 0; var bytes: Int64 = 0
        var paths = Set<String>()
        var enumerationError: Error?
        guard let enumerator = SafeFiles.fm.enumerator(at: root, includingPropertiesForKeys: nil, errorHandler: { _, error in enumerationError = error; return false }) else { throw HarborError("Cannot read the app bundle.") }
        for case let file as URL in enumerator {
            try cancellation.check(); count += 1
            let relative = String(file.path.dropFirst(base.count))
            guard paths.insert(relative.precomposedStringWithCanonicalMapping.lowercased()).inserted, count <= 150_000 else { throw HarborError("App bundle contains colliding paths or too many files.") }
            let attributes = try SafeFiles.fm.attributesOfItem(atPath: file.path)
            let type = attributes[.type] as? FileAttributeType
            switch type {
            case .typeSymbolicLink:
                let target = try SafeFiles.fm.destinationOfSymbolicLink(atPath: file.path)
                guard !target.hasPrefix("/"), !target.contains("\\"), file.resolvingSymlinksInPath().path.hasPrefix(base), SafeFiles.fm.fileExists(atPath: file.path) else {
                    throw HarborError("App bundle contains an escaping, broken, or cyclic symbolic link.")
                }
            case .typeRegular:
                guard (attributes[.referenceCount] as? NSNumber)?.intValue == 1 else { throw HarborError("Hard links are not supported in app bundles.") }
                bytes += (attributes[.size] as? NSNumber)?.int64Value ?? 0
            case .typeDirectory: break
            default: throw HarborError("App bundle contains a special file.")
            }
            guard bytes <= 12_884_901_888, ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o6000 == 0 else { throw HarborError("App bundle is too large or contains privileged file modes.") }
        }
        if let enumerationError { throw enumerationError }
    }
    /// Thin Mach-O only; all native code, including helpers, must be arm64. Returns false for non-Mach-O data.
    static func inspectMachO(_ url: URL, declaredMinimum: String) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        guard let header = try handle.read(upToCount: 32), header.count >= 4 else { return false }
        func u32(_ data: Data, _ i: Int) -> UInt32 { data[i..<i+4].enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * $1.offset) } }
        let magic = u32(header, 0)
        if [0xbebafeca, 0xbfbafeca, 0xcafebabe, 0xcafebabf, 0xfeedface, 0xcefaedfe, 0xcffaedfe].contains(magic) {
            throw HarborError("Universal, Intel or unsupported native code found in \(url.lastPathComponent). Harbor requires arm64 only.")
        }
        guard magic == 0xfeedfacf else { return false }
        guard header.count == 32, u32(header, 4) == 0x0100000c else { throw HarborError("Non-arm64 native code found in \(url.lastPathComponent).") }
        let ncmds = Int(u32(header, 16)), size = Int(u32(header, 20))
        guard size <= 4_194_304, ncmds <= 10000, let commands = try handle.read(upToCount: size), commands.count == size else { throw HarborError("Malformed Mach-O load commands.") }
        var i = 0; var foundMinimum = false
        for _ in 0..<ncmds {
            guard i + 8 <= commands.count else { throw HarborError("Truncated Mach-O load commands.") }
            let cmd = u32(commands, i), len = Int(u32(commands, i+4))
            guard len >= 8, i + len <= commands.count else { throw HarborError("Malformed Mach-O load command size.") }
            var min: UInt32?
            if cmd == 0x32 {
                guard len >= 24, u32(commands, i+8) == 1 else { throw HarborError("The executable targets an unsupported Apple platform.") }
                min = u32(commands, i+12)
            } else if cmd == 0x24 {
                guard len >= 16 else { throw HarborError("Malformed minimum OS command.") }; min = u32(commands, i+8)
            }
            if let min {
                foundMinimum = true
                let actual = "\(min >> 16).\((min >> 8) & 255).\(min & 255)"
                guard try Versions.compare(actual, declaredMinimum) != .orderedDescending else { throw HarborError("\(url.lastPathComponent) requires macOS \(actual), above the app's declared minimum.") }
            }
            i += len
        }
        guard foundMinimum, i == size else { throw HarborError("Native code has no supported macOS deployment target or malformed commands.") }
        return true
    }
}
