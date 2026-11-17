import AppKit
import Foundation

@MainActor
enum SafariPageButton {
  static var bookmarkURL: String {
    let resource = Bundle.module.url(forResource: "PagePicker", withExtension: "js")!
    let script = (try? String(contentsOf: resource, encoding: .utf8)) ?? ""
    // Encode line breaks as well, so a // comment cannot swallow subsequent code.
    return "javascript:"
      + (script.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
  }

  static func openSetup() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "Eucrante-Safari-Setup", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("Safari Button.html")
    let html = """
      <!doctype html><html lang="en"><meta charset="utf-8"><title>Eucrante Safari Button</title>
      <style>body{font:18px -apple-system,sans-serif;max-width:680px;margin:80px auto;padding:24px;color:#17202b;background:#f6f8fb}a{display:inline-block;background:#176a65;color:white;padding:18px 26px;border-radius:12px;text-decoration:none}li{margin:16px 0}code{font-size:15px}</style>
      <h1>Save from the page you're on</h1><p>Drag this button into Safari's Favorites bar:</p>
      <p><a href="\(bookmarkURL)">↓ Eucrante</a></p>
      <ol><li>Show the bar with <strong>View → Show Favorites Bar</strong>.</li>
      <li>Drag the green Eucrante button onto the bar.</li>
      <li>Open a media page and click the Favorite. Allow Safari to open Eucrante if asked.</li></ol>
      <p>Eucrante checks visible media links and opens a picker. Hover for details, then choose an item to edit its metadata, times, quality and square cover.</p>
      <p>The button runs only when clicked. It sends page links and titles to the local app, never cookies. Checking a link contacts that provider through Eucrante. Sign in to YouTube in the app when needed.</p>
      <p>Up to 100 unique links are scanned per click; unloaded items, protected streams and sites that block bookmarklets may be unavailable. You can still paste a direct link into Eucrante.</p></html>
      """
    try html.write(to: url, atomically: true, encoding: .utf8)
    guard
      let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")
    else {
      NSWorkspace.shared.open(url)
      return
    }
    NSWorkspace.shared.open(
      [url], withApplicationAt: safari, configuration: NSWorkspace.OpenConfiguration())
  }
}
