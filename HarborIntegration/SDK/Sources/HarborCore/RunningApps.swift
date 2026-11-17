import AppKit

public enum RunningApps {
    public static func hasInstance(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).filter( { !$0.isTerminated }).isEmpty
    }
    @MainActor public static func requestQuit(bundleIdentifier: String) -> Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        return apps.map { $0.terminate() }.allSatisfy { $0 }
    }
}
