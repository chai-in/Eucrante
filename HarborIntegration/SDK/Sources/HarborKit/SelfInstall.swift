import AppKit
import SwiftUI

/// First-launch installation shared by Harbor and its apps. Never replaces an existing app.
@MainActor public enum SelfInstall {
    private static var checked = false

    public static func offerIfNeeded() async {
        guard !checked else { return }
        checked = true
        let source = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let arguments = ProcessInfo.processInfo.arguments
        if let marker = arguments.firstIndex(of: "--harbor-install-complete"),
           arguments.indices.contains(marker + 1) {
            let volume = URL(fileURLWithPath: arguments[marker + 1])
            // Arguments only request a confirmation UI; mounted-image inventory supplies cleanup paths.
            if !source.path.hasPrefix(volume.path + "/"), let image = await mountedImage(for: volume) {
                await finishInstallation(at: source, volume: volume, image: image)
                return
            }
        }
        guard source.pathExtension == "app",
              let values = try? source.resourceValues(forKeys: [.volumeURLKey]),
              let volume = values.allValues[.volumeURLKey] as? URL,
              await mountedImage(for: volume) != nil else { return }

        let name = source.deletingPathExtension().lastPathComponent
        let prompt = NSAlert()
        prompt.messageText = "Install \(name)?"
        prompt.informativeText = "Copy this app to Applications and open the installed copy."
        prompt.addButton(withTitle: "Install")
        prompt.addButton(withTitle: "Continue Without Installing")
        guard prompt.runModal() == .alertFirstButtonReturn else { return }

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 90),
                            styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Installing \(name)…"
        let progress = NSProgressIndicator(frame: NSRect(x: 24, y: 36, width: 312, height: 16))
        progress.isIndeterminate = true
        progress.startAnimation(nil)
        panel.contentView?.addSubview(progress)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        do {
            let destination = try await Task.detached {
                let manager = FileManager.default
                let system = URL(fileURLWithPath: "/Applications", isDirectory: true)
                let directory = manager.isWritableFile(atPath: system.path)
                    ? system : manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
                return try copyApplication(from: source, to: directory)
            }.value
            panel.close()
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.arguments = ["--harbor-install-complete", volume.path]
            _ = try await NSWorkspace.shared.openApplication(at: destination, configuration: configuration)
            NSApp.terminate(nil)
        } catch {
            panel.close()
            showError("Couldn’t finish installation", error)
        }
    }

    private static func finishInstallation(at destination: URL, volume: URL, image: URL) async {
        let installed = NSAlert()
        installed.messageText = "\(destination.deletingPathExtension().lastPathComponent) is installed"
        installed.informativeText = "You’re running the installed copy."
        installed.addButton(withTitle: "Continue")
        installed.addButton(withTitle: "Show in Finder")
        installed.showsSuppressionButton = true
        installed.suppressionButton?.title = "Eject disk image and move download to Trash"
        installed.suppressionButton?.state = .off
        let response = installed.runModal()
        if response == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        }
        guard installed.suppressionButton?.state == .on else { return }
        do {
            // Eject from the installed process, after the source has had time to exit.
            for _ in 0..<50 {
                let sourceStillRunning = NSWorkspace.shared.runningApplications.contains {
                    $0.bundleURL?.path.hasPrefix(volume.path + "/") == true
                }
                if !sourceStillRunning { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            try NSWorkspace.shared.unmountAndEjectDevice(at: volume)
            _ = try await NSWorkspace.shared.recycle([image])
        } catch {
            showError("The app is installed, but disk image cleanup failed", error, reveal: image)
        }
    }

    /// Stages a complete copy on the destination volume before publishing it with a no-clobber move.
    nonisolated static func copyApplication(from source: URL, to directory: URL) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        guard !manager.fileExists(atPath: destination.path) else {
            throw NSError(domain: "HarborSelfInstall", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "An app already exists at \(destination.path). Open that copy or use its update workflow. Your existing app was left untouched."])
        }
        let staging = directory.appendingPathComponent(".harbor-install-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: staging) }
        let copy = staging.appendingPathComponent(source.lastPathComponent)
        // Foundation preserves bundle metadata and extended attributes, including quarantine.
        try manager.copyItem(at: source, to: copy)
        guard let original = Bundle(url: source), let copied = Bundle(url: copy),
              original.bundleIdentifier != nil, original.bundleIdentifier == copied.bundleIdentifier,
              let executable = copied.executableURL, manager.isExecutableFile(atPath: executable.path) else {
            throw NSError(domain: "HarborSelfInstall", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "The copied application is incomplete."])
        }
        try manager.moveItem(at: copy, to: destination)
        return destination
    }

    private static func mountedImage(for volume: URL) async -> URL? {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = ["info", "-plist"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0,
                      let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let images = plist["images"] as? [[String: Any]] else { return nil }
                for image in images {
                    let entities = image["system-entities"] as? [[String: Any]] ?? []
                    guard entities.contains(where: { ($0["mount-point"] as? String) == volume.path }),
                          let path = image["image-path"] as? String, path.hasPrefix("/") else { continue }
                    let url = URL(fileURLWithPath: path)
                    guard url.pathExtension.lowercased() == "dmg" else { continue }
                    return url
                }
            } catch { return nil }
            return nil
        }.value
    }

    private static func showError(_ title: String, _ error: Error, reveal: URL? = nil) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        if reveal != nil { alert.addButton(withTitle: "Show Download in Finder") }
        if alert.runModal() == .alertSecondButtonReturn, let reveal {
            NSWorkspace.shared.activateFileViewerSelecting([reveal])
        }
    }
}

public extension View {
    /// Attach once to the main window; subsequent window appearances are ignored.
    func offerAppInstallation() -> some View {
        task { await SelfInstall.offerIfNeeded() }
    }
}
