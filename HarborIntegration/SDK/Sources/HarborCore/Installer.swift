import Foundation
import Darwin
import HarborKit

public struct InstalledApp: Equatable, Sendable {
    public let url: URL
    public let version: String
    public let build: String
    public static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool {
        lhs.url.standardizedFileURL.path == rhs.url.standardizedFileURL.path && lhs.version == rhs.version && lhs.build == rhs.build
    }
    public static func read(_ url: URL, app: AppDefinition) throws -> InstalledApp {
        try SafeFiles.noSymlinkAncestors(url)
        let data = try SafeFiles.read(url.appendingPathComponent("Contents/Info.plist"), maxBytes: 1_048_576)
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == app.bundleIdentifier,
              let version = info["CFBundleShortVersionString"] as? String, let build = info["CFBundleVersion"] as? String else {
            throw HarborError("An unrelated or unreadable app occupies \(url.path). Harbor will not replace it.")
        }
        _ = try Versions.parts(version); _ = try Versions.parts(build)
        return .init(url: url, version: version, build: build)
    }
}

public enum InstallCheckpoint: String, CaseIterable { case staged, journaled, replaced, validated, committed }
struct Journal: Codable {
    enum Phase: String, Codable { case staging, ready, committed }
    let id: String
    let appID: String
    var phase: Phase
    var previousDigest: String?
    var candidateDigest: String?
}
public struct RecoveryReport: Sendable {
    public var recovered = 0
    public var issues: [String] = []
    public init() {}
}

/// Only app bundles inside a caller-selected application folder are mutated. App data is never in scope.
public final class Installer: @unchecked Sendable {
    public let applications: URL
    private let transactions: URL
    public init(applications: URL) {
        self.applications = applications.standardizedFileURL
        transactions = self.applications.appendingPathComponent(".harbor-transactions", isDirectory: true)
    }
    public func install(source: URL, app: AppDefinition, release: Release?, expected: InstalledApp?,
                        allowSameVersion: Bool = false, catalogExpiresAt: Date? = nil, cancellation: Cancellation = Cancellation(),
                        isRunning: (() -> Bool)? = nil, progress: (String, Double) -> Void = { _, _ in },
                        checkpoint: (InstallCheckpoint) throws -> Void = { _ in }) throws -> InstalledApp {
        guard OwnedApps.all.contains(app) else { throw HarborError("This application is not in Harbor's trusted identity registry.") }
        guard release == nil || (catalogExpiresAt ?? .distantPast) > Date() else { throw HarborError("The catalog authorization is expired. Refresh before installing.") }
        guard app.id != "harbor" else { throw HarborError("Use Harbor's signed Sparkle update flow to update Harbor itself.") }
        return try locked {
            let recovery = recoverLocked()
            guard recovery.issues.isEmpty else { throw HarborError(recovery.issues.joined(separator: "\n")) }
            let destination = applications.appendingPathComponent(app.bundleName)
            try checkDestination(destination, app: app, expected: expected)
            guard !(isRunning?() ?? RunningApps.hasInstance(bundleIdentifier: app.bundleIdentifier)) else { throw HarborError("Quit \(app.name), save your work, then retry. Harbor does not force-quit apps.") }
            let transaction = transactions.appendingPathComponent(UUID().uuidString)
            try SafeFiles.ensureDirectory(transaction, privateMode: true)
            let candidate = transaction.appendingPathComponent("Candidate.app")
            let journalURL = transaction.appendingPathComponent("journal.json")
            var journal = Journal(id: transaction.lastPathComponent, appID: app.id, phase: .staging)
            try save(journal, journalURL)
            do {
                try cancellation.check(); progress("Staging application", 0.12)
                try BundleInspector.validateTree(source, cancellation: cancellation)
                try SafeFiles.fm.copyItem(at: source, to: candidate)
                try SafeFiles.quarantine(candidate)
                progress("Checking identity and native code", 0.35)
                let facts = try BundleInspector.inspect(candidate, app: app, release: release, cancellation: cancellation)
                if let expected {
                    guard try Versions.compare(facts.version, expected.version) != .orderedAscending,
                          try Versions.compare(facts.build, expected.build) == .orderedDescending ||
                            (allowSameVersion && facts.build == expected.build) else {
                        throw HarborError("Harbor will not downgrade an installed app. A release update must increase its build number.")
                    }
                }
                try checkpoint(.staged)
                journal.candidateDigest = try treeDigest(candidate, cancellation: cancellation)
                if SafeFiles.exists(destination) { journal.previousDigest = try treeDigest(destination, cancellation: cancellation) }
                try syncTree(candidate)
                journal.phase = .ready; try save(journal, journalURL)
                try checkpoint(.journaled)
                // Cancellation stops here; once replacement starts, finish validation or restore the previous app.
                try cancellation.check()
                try checkDestination(destination, app: app, expected: expected)
                if let digest = journal.previousDigest {
                    guard try treeDigest(destination) == digest else { throw HarborError("The installed app changed during staging. Refresh and retry.") }
                }
                guard release == nil || (catalogExpiresAt ?? .distantPast) > Date() else { throw HarborError("The catalog expired during staging. Refresh and try again.") }
                guard !(isRunning?() ?? RunningApps.hasInstance(bundleIdentifier: app.bundleIdentifier)) else { throw HarborError("\(app.name) opened during staging. Quit it and retry.") }
                progress("Replacing application safely", 0.72)
                let flags = journal.previousDigest == nil ? UInt32(RENAME_EXCL) : UInt32(RENAME_SWAP)
                guard renamex_np(candidate.path, destination.path, flags) == 0 else {
                    throw HarborError("macOS could not replace this app (\(String(cString: strerror(errno)))). Check folder access and free space, then retry.")
                }
                try SafeFiles.sync(applications); try SafeFiles.sync(transaction)
                try checkpoint(.replaced)
                guard try treeDigest(destination) == journal.candidateDigest else { throw HarborError("Installed app failed its final integrity check.") }
                _ = try BundleInspector.inspect(destination, app: app, release: release)
                try checkpoint(.validated)
                journal.phase = .committed; try save(journal, journalURL)
                try checkpoint(.committed)
                // A completed update no longer needs the previous binary. User libraries/settings were never moved.
                try? SafeFiles.fm.removeItem(at: transaction)
                progress("Installation complete", 1)
                return try InstalledApp.read(destination, app: app)
            } catch {
                // Test crash sentinel deliberately leaves the on-disk transaction for a fresh instance to recover.
                if error is SimulatedInterruption { throw error }
                do { try recoverTransaction(transaction) }
                catch let recoveryError { throw HarborError("\(error.localizedDescription) Recovery also needs attention: \(recoveryError.localizedDescription) The transaction is retained in \(transaction.path).") }
                throw error
            }
        }
    }
    public func recover() -> RecoveryReport {
        do { return try locked { recoverLocked() } }
        catch { var r = RecoveryReport(); r.issues = [error.localizedDescription]; return r }
    }
    private func checkDestination(_ url: URL, app: AppDefinition, expected: InstalledApp?) throws {
        try SafeFiles.noSymlinkAncestors(url)
        if SafeFiles.exists(url) {
            guard let expected, try InstalledApp.read(url, app: app) == expected else { throw HarborError("The installation changed. Refresh the catalog before replacing an app.") }
        } else if expected != nil { throw HarborError("The installed app moved or disappeared. Refresh and retry.") }
    }
    private func locked<T>(_ body: () throws -> T) throws -> T {
        try SafeFiles.ensureDirectory(applications)
        try SafeFiles.ensureDirectory(transactions, privateMode: true)
        let attr = try SafeFiles.fm.attributesOfItem(atPath: transactions.path)
        guard (attr[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw HarborError("Harbor's transaction folder belongs to another account.") }
        let lock = transactions.appendingPathComponent("lock")
        let fd = open(lock.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw HarborError("Cannot lock this Applications folder.") }
        defer { flock(fd, LOCK_UN); close(fd) }
        var stat = Darwin.stat()
        guard fstat(fd, &stat) == 0, stat.st_uid == getuid(), stat.st_nlink == 1,
              stat.st_mode & S_IFMT == S_IFREG, flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw HarborError("Another Harbor installation is active. Wait for it to finish, then retry.") }
        return try body()
    }
    private func recoverLocked() -> RecoveryReport {
        var report = RecoveryReport()
        do {
            for dir in try SafeFiles.fm.contentsOfDirectory(at: transactions, includingPropertiesForKeys: nil) where dir.lastPathComponent != "lock" {
                do { try recoverTransaction(dir); report.recovered += 1 }
                catch { report.issues.append("Recovery paused for \(dir.lastPathComponent): \(error.localizedDescription)") }
            }
        } catch { report.issues.append(error.localizedDescription) }
        return report
    }
    private func recoverTransaction(_ dir: URL) throws {
        try SafeFiles.noSymlinkAncestors(dir)
        guard UUID(uuidString: dir.lastPathComponent) != nil else { throw HarborError("Unknown transaction content retained for inspection.") }
        let url = dir.appendingPathComponent("journal.json")
        let journal = try ContractJSON.decoder().decode(Journal.self, from: SafeFiles.read(url, maxBytes: 65536))
        guard journal.id == dir.lastPathComponent, let app = OwnedApps.all.first(where: { $0.id == journal.appID }), app.id != "harbor" else { throw HarborError("Invalid recovery journal. No installed app was changed.") }
        let destination = applications.appendingPathComponent(app.bundleName)
        let candidate = dir.appendingPathComponent("Candidate.app")
        try SafeFiles.noSymlinkAncestors(destination); try SafeFiles.noSymlinkAncestors(candidate)
        if journal.phase == .staging { try SafeFiles.fm.removeItem(at: dir); return }
        guard let newDigest = journal.candidateDigest, newDigest.count == 64 else { throw HarborError("Incomplete recovery journal.") }
        let installedDigest = SafeFiles.exists(destination) ? try treeDigest(destination) : nil
        if journal.phase == .committed {
            guard installedDigest == newDigest else { throw HarborError("The installed app changed after the update. Its previous binary is retained; inspect the transaction folder.") }
        } else if installedDigest == newDigest {
            // A user might have opened the newly installed app after a crash. Never exchange a running bundle.
            guard !RunningApps.hasInstance(bundleIdentifier: app.bundleIdentifier) else { throw HarborError("Quit \(app.name), then retry recovery.") }
            if let oldDigest = journal.previousDigest {
                guard SafeFiles.exists(candidate), try treeDigest(candidate) == oldDigest else { throw HarborError("The previous app cannot be verified. Both locations have been preserved.") }
                guard renamex_np(candidate.path, destination.path, UInt32(RENAME_SWAP)) == 0 else { throw HarborError("Cannot restore the previous application.") }
            } else {
                guard !SafeFiles.exists(candidate), renamex_np(destination.path, candidate.path, UInt32(RENAME_EXCL)) == 0 else { throw HarborError("Cannot roll back the interrupted first installation.") }
            }
            try SafeFiles.sync(applications); try SafeFiles.sync(dir)
        } else {
            // Ready journal before the atomic rename: the existing app should be exactly as it was.
            guard installedDigest == journal.previousDigest else { throw HarborError("The destination changed outside Harbor. Recovery kept every file for inspection.") }
        }
        try SafeFiles.fm.removeItem(at: dir)
    }
    private func save(_ journal: Journal, _ url: URL) throws { try SafeFiles.atomicWrite(ContractJSON.encoder().encode(journal), to: url) }
    private func syncTree(_ root: URL) throws {
        let entries = SafeFiles.fm.enumerator(at: root, includingPropertiesForKeys: nil)!
        var directories: [URL] = []
        for case let url as URL in entries {
            let a = try SafeFiles.fm.attributesOfItem(atPath: url.path)
            if a[.type] as? FileAttributeType == .typeRegular { try SafeFiles.sync(url) }
            if a[.type] as? FileAttributeType == .typeDirectory { directories.append(url) }
        }
        for directory in directories.reversed() { try SafeFiles.sync(directory) }
        try SafeFiles.sync(root)
    }
    public func treeDigest(_ root: URL, cancellation: Cancellation = Cancellation()) throws -> String {
        try SafeFiles.noSymlinkAncestors(root)
        guard let e = SafeFiles.fm.enumerator(atPath: root.path) else { throw HarborError("Cannot read application content.") }
        let paths = e.allObjects.compactMap { $0 as? String }.sorted()
        guard paths.count <= 150000 else { throw HarborError("Application has too many files.") }
        var records = Data(); var total: Int64 = 0
        for path in paths {
            let url = root.appendingPathComponent(path)
            try cancellation.check()
            let a = try SafeFiles.fm.attributesOfItem(atPath: url.path)
            var record = [path, String((a[.posixPermissions] as? NSNumber)?.intValue ?? 0)]
            switch a[.type] as? FileAttributeType {
            case .typeRegular:
                total += (a[.size] as? NSNumber)?.int64Value ?? 0
                guard total <= 12_884_901_888 else { throw HarborError("Application is too large.") }
                record += ["file", try Digests.sha256(file: url, cancellation: cancellation.check)]
            case .typeDirectory: record += ["directory"]
            case .typeSymbolicLink: record += ["link", try SafeFiles.fm.destinationOfSymbolicLink(atPath: url.path)]
            default: throw HarborError("Special files cannot be installed.")
            }
            records.append(try JSONEncoder().encode(record)); records.append(10)
        }
        return Digests.sha256(records)
    }
}
/// Internal crash fixture seam. Production code never constructs this error.
struct SimulatedInterruption: Error {}
