import Foundation

public enum FileDestinationResolver {
  public static func uniqueDestination(
    for filename: String,
    in directory: URL,
    fileManager: FileManager = .default,
    reservedPaths: Set<String> = []
  ) -> URL {
    let proposed = directory.appendingPathComponent(filename, isDirectory: false)
    guard fileManager.fileExists(atPath: proposed.path) || reservedPaths.contains(proposed.path)
    else { return proposed }

    let extensionName = proposed.pathExtension
    let stem = proposed.deletingPathExtension().lastPathComponent
    for suffix in 2...9_999 {
      let candidateName =
        extensionName.isEmpty
        ? "\(stem) \(suffix)"
        : "\(stem) \(suffix).\(extensionName)"
      let candidate = directory.appendingPathComponent(candidateName, isDirectory: false)
      if !fileManager.fileExists(atPath: candidate.path), !reservedPaths.contains(candidate.path) {
        return candidate
      }
    }
    return directory.appendingPathComponent(
      UUID().uuidString + (extensionName.isEmpty ? "" : ".\(extensionName)"))
  }
}

public enum FilenameSanitizer {
  public static func sanitize(_ input: String, maximumLength: Int = 180) -> String {
    var value =
      input
      .replacingOccurrences(of: "\\", with: "-")
      .replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: ":", with: "-")

    value.unicodeScalars.removeAll { scalar in
      CharacterSet.controlCharacters.contains(scalar)
    }
    value = value.trimmingCharacters(
      in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
    guard !value.isEmpty, value != ".", value != ".." else { return "download" }
    guard value.count > maximumLength else { return value }

    let sourceURL = URL(fileURLWithPath: value)
    let ext = sourceURL.pathExtension
    let extensionBudget = ext.isEmpty ? 0 : ext.count + 1
    let stemBudget = max(1, maximumLength - extensionBudget)
    let stem = String(sourceURL.deletingPathExtension().lastPathComponent.prefix(stemBudget))
    return ext.isEmpty ? stem : "\(stem).\(ext)"
  }
}
