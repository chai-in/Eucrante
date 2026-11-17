import Foundation
import CArchive
import Darwin

public enum ArchiveExtractor {
    /// libarchive decodes ZIP; Harbor creates only bounded regular files/directories, then confined symlinks.
    public static func extract(_ archiveURL: URL, to destination: URL, bundleName: String, cancellation: Cancellation = Cancellation()) throws -> URL {
        guard !SafeFiles.exists(destination) else { throw HarborError("Extraction requires a new private staging folder.") }
        try SafeFiles.ensureDirectory(destination, privateMode: true)
        var completed = false
        defer { if !completed { try? SafeFiles.fm.removeItem(at: destination) } }
        guard let archive = archive_read_new() else { throw HarborError("Cannot create archive reader.") }
        defer { archive_read_free(archive) }
        archive_read_support_filter_none(archive)
        archive_read_support_format_zip(archive)
        guard archive_read_open_filename(archive, archiveURL.path, 65536) == ARCHIVE_OK else { throw HarborError("Cannot read this ZIP archive.") }
        var entry: OpaquePointer?
        var entries = Set<String>(); var links: [(String, String)] = []; var total: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            try cancellation.check()
            let status = archive_read_next_header(archive, &entry)
            if status == ARCHIVE_EOF { break }
            guard status == ARCHIVE_OK, let entry, let raw = archive_entry_pathname_utf8(entry) else { throw HarborError("The archive is corrupt or has an invalid entry name.") }
            let path = String(cString: raw)
            let clean = path.hasSuffix("/") ? String(path.dropLast()) : path
            let parts = clean.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard !clean.isEmpty, clean.utf8.count <= 4096, parts.first == bundleName,
                  !path.contains("\\"), !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 255 }),
                  entries.count < 150000, entries.insert(clean.precomposedStringWithCanonicalMapping.lowercased()).inserted,
                  archive_entry_hardlink(entry) == nil, archive_entry_is_encrypted(entry) == 0,
                  archive_entry_perm(entry) & 0o6000 == 0 else { throw HarborError("The archive contains unsafe, duplicate, encrypted or unsupported paths.") }
            let output = destination.appendingPathComponent(clean)
            let type = archive_entry_filetype(entry)
            if type == UInt32(S_IFDIR) {
                try SafeFiles.ensureDirectory(output)
            } else if type == UInt32(S_IFLNK) {
                guard let rawTarget = archive_entry_symlink_utf8(entry) else { throw HarborError("Invalid symbolic link.") }
                let target = String(cString: rawTarget)
                guard !target.isEmpty, !target.hasPrefix("/"), !target.contains("\\"), target.utf8.count <= 4096 else { throw HarborError("Unsafe symbolic link target.") }
                let resolved = output.deletingLastPathComponent().appendingPathComponent(target).standardizedFileURL
                let root = destination.appendingPathComponent(bundleName).path + "/"
                guard resolved.path.hasPrefix(root) else { throw HarborError("A symbolic link escapes the application.") }
                links.append((clean, target))
            } else if type == UInt32(S_IFREG) {
                let expected = archive_entry_size(entry)
                guard expected >= 0, expected <= 4_294_967_296, total + expected <= 12_884_901_888 else { throw HarborError("The archive expands beyond Harbor's size limit.") }
                try SafeFiles.ensureDirectory(output.deletingLastPathComponent())
                guard !SafeFiles.exists(output) else { throw HarborError("An archive file conflicts with a directory.") }
                guard SafeFiles.fm.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw HarborError("Cannot stage archive content. Check available storage.") }
                let handle = try FileHandle(forWritingTo: output)
                do {
                    var written: Int64 = 0
                    while true {
                        try cancellation.check()
                        let count = archive_read_data(archive, &buffer, buffer.count)
                        guard count >= 0 else { throw HarborError("The archive is corrupt or failed its integrity check.") }
                        if count == 0 { break }
                        written += Int64(count)
                        guard written <= expected else { throw HarborError("Archive entry exceeds its declared size.") }
                        try handle.write(contentsOf: Data(buffer[0..<count]))
                    }
                    guard written == expected else { throw HarborError("The archive contains a truncated file.") }
                    try handle.synchronize(); try handle.close()
                    let mode = Int(archive_entry_perm(entry)) & 0o777
                    try SafeFiles.fm.setAttributes([.posixPermissions: mode & ~0o022], ofItemAtPath: output.path)
                    total += written
                } catch { try? handle.close(); throw error }
            } else { throw HarborError("Install archives may contain only regular files, directories and confined symbolic links.") }
        }
        guard archive_read_has_encrypted_entries(archive) <= 0 else { throw HarborError("Encrypted archives are not supported.") }
        for (path, target) in links {
            let key = path.precomposedStringWithCanonicalMapping.lowercased()
            guard !entries.contains(where: { $0.hasPrefix(key + "/") }) else { throw HarborError("Archive entries cannot be placed beneath a symbolic link.") }
            let file = destination.appendingPathComponent(path)
            try SafeFiles.ensureDirectory(file.deletingLastPathComponent())
            try SafeFiles.fm.createSymbolicLink(atPath: file.path, withDestinationPath: target)
        }
        let app = destination.appendingPathComponent(bundleName)
        try BundleInspector.validateTree(app, cancellation: cancellation)
        guard SafeFiles.exists(app.appendingPathComponent("Contents/Info.plist")) else { throw HarborError("The archive does not contain the expected app bundle.") }
        completed = true
        return app
    }
}
