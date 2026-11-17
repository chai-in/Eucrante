import Foundation
import Darwin

public enum SafeFiles {
    public static let fm = FileManager.default
    public static func exists(_ url: URL) -> Bool { (try? fm.attributesOfItem(atPath: url.path)) != nil }
    public static func ensureDirectory(_ url: URL, privateMode: Bool = false) throws {
        try noSymlinkAncestors(url)
        if !exists(url) { try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: privateMode ? 0o700 : 0o755]) }
        try noSymlinkAncestors(url)
        guard (try fm.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeDirectory else { throw HarborError("Expected a real folder: \(url.path)") }
        if privateMode { try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path) }
    }
    public static func noSymlinkAncestors(_ url: URL) throws {
        var current = url.standardizedFileURL
        while current.path != "/" {
            if exists(current), (try fm.attributesOfItem(atPath: current.path)[.type] as? FileAttributeType) == .typeSymbolicLink {
                // Foundation may shorten /private/var back to /var. Allow only these root-owned macOS aliases.
                let aliases = ["/var": "/private/var", "/tmp": "/private/tmp", "/etc": "/private/etc"]
                if let expected = aliases[current.path],
                   [expected, String(expected.dropFirst())].contains(try fm.destinationOfSymbolicLink(atPath: current.path)),
                   (try fm.attributesOfItem(atPath: current.path)[.ownerAccountID] as? NSNumber)?.uint32Value == 0 {
                    current.deleteLastPathComponent(); continue
                }
                throw HarborError("Symbolic links cannot be used as an installation location: \(current.path)")
            }
            current.deleteLastPathComponent()
        }
    }
    public static func regularFile(_ url: URL, maxBytes: Int64) throws -> Int64 {
        let a = try fm.attributesOfItem(atPath: url.path)
        guard a[.type] as? FileAttributeType == .typeRegular, let size = a[.size] as? NSNumber, size.int64Value <= maxBytes,
              (a[.referenceCount] as? NSNumber)?.intValue == 1 else { throw HarborError("Expected a bounded file with no links: \(url.lastPathComponent)") }
        return size.int64Value
    }
    public static func read(_ url: URL, maxBytes: Int64) throws -> Data {
        _ = try regularFile(url, maxBytes: maxBytes)
        return try Data(contentsOf: url)
    }
    public static func atomicWrite(_ data: Data, to url: URL) throws {
        try noSymlinkAncestors(url.deletingLastPathComponent())
        if exists(url) { _ = try regularFile(url, maxBytes: 16_777_216) }
        try data.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try sync(url)
        try sync(url.deletingLastPathComponent())
    }
    public static func sync(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw HarborError("Cannot open recovery data for synchronization.") }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw HarborError("Cannot save recovery data to disk.") }
    }
    public static func quarantine(_ url: URL) throws {
        // Add download provenance; never remove or clear existing quarantine.
        let value = String(format: "0083;%08x;Harbor;", Int(Date().timeIntervalSince1970))
        let status = value.withCString { setxattr(url.path, "com.apple.quarantine", $0, strlen($0), 0, XATTR_CREATE) }
        guard status == 0 || errno == EEXIST else { throw HarborError("Could not retain Gatekeeper download provenance.") }
    }
}

public final class Cancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    public func check() throws { lock.lock(); let value = cancelled; lock.unlock(); if value { throw CancellationError() } }
}
public struct ProcessOutput { public let status: Int32; public let text: String }
public enum SystemProcess {
    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 120, cancellation: Cancellation? = nil) throws -> ProcessOutput {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("harbor-process-\(UUID().uuidString)")
        try SafeFiles.ensureDirectory(dir, privateMode: true); defer { try? SafeFiles.fm.removeItem(at: dir) }
        let output = dir.appendingPathComponent("output")
        SafeFiles.fm.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: output); defer { try? handle.close() }
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = handle; process.standardError = handle; process.standardInput = FileHandle.nullDevice
        try process.run()
        let end = Date().addingTimeInterval(timeout)
        do {
            while process.isRunning {
                try cancellation?.check()
                if Date() > end { throw HarborError("\(URL(fileURLWithPath: executable).lastPathComponent) timed out. Try again.") }
                Thread.sleep(forTimeInterval: 0.03)
            }
        } catch {
            process.terminate()
            let stop = Date().addingTimeInterval(2)
            while process.isRunning && Date() < stop { Thread.sleep(forTimeInterval: 0.03) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit(); throw error
        }
        process.waitUntilExit()
        let data = try SafeFiles.read(output, maxBytes: 4_194_304)
        return ProcessOutput(status: process.terminationStatus, text: String(decoding: data, as: UTF8.self))
    }
}
