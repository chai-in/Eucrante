import EucranteCore
import XCTest

@testable import EucranteApp

@MainActor
final class PageScanBenchmarkTests: XCTestCase {
  func testLiveScanAndRepeat() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let input = env["EUCRANTE_SCAN_INPUT"] else {
      throw XCTSkip("Opt-in real provider benchmark: set EUCRANTE_SCAN_INPUT to a URL list.")
    }
    let urls = try String(contentsOfFile: input, encoding: .utf8).split(separator: "\n").map(
      String.init)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let acquirer = LocalMediaAcquirer()
    let model = PagePickerModel(
      previewer: acquirer, session: BenchmarkSession(), workspace: DownloadWorkspace(root: root))
    let payload: [String: Any] = [
      "page": "https://www.youtube.com/", "title": "Full-format scan benchmark",
      "truncated": false, "items": urls.map { ["url": $0, "title": "Benchmark item"] },
    ]
    var components = URLComponents(string: "eucrante://page")!
    components.queryItems = [
      URLQueryItem(
        name: "payload",
        value: String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self))
    ]
    let selection = try PageMediaSelection.decode(components.url!)
    let began = ContinuousClock.now
    model.load(selection)
    var first: Double?
    while model.running {
      if first == nil, model.rows.contains(where: { $0.preview != nil }) {
        first = seconds(began.duration(to: .now))
      }
      guard began.duration(to: .now) < .seconds(400) else {
        await model.stop()
        XCTFail("Scan timed out")
        return
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    let cold = seconds(began.duration(to: .now))
    let verified = model.rows.filter { $0.preview != nil }.count
    let formats = model.rows.compactMap { $0.preview?.formats.count }
    let failed = model.rows.compactMap { $0.error }
    let repeated = ContinuousClock.now
    model.load(selection)
    while model.running { try await Task.sleep(for: .milliseconds(10)) }
    let warm = seconds(repeated.duration(to: .now))
    await model.stop()
    let result: [String: Any] = [
      "items": urls.count, "verified": verified,
      "coldSeconds": cold, "firstResultSeconds": first ?? cold, "repeatSeconds": warm,
      "formats": formats, "failures": failed,
      "unavailable": model.rows.filter { $0.error != nil }.map { $0.item.url.absoluteString },
      "workers": PagePickerModel.workerLimit,
    ]
    let data = try JSONSerialization.data(
      withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
    if let output = env["EUCRANTE_SCAN_OUTPUT"] { try data.write(to: URL(fileURLWithPath: output)) }
    print("EUCRANTE_SCAN_BENCHMARK \(String(decoding: data, as: UTF8.self))")
    XCTAssertGreaterThanOrEqual(
      verified, Int(env["EUCRANTE_SCAN_EXPECTED"] ?? "") ?? urls.count,
      failed.joined(separator: "\n"))
    XCTAssertEqual(model.rows.compactMap(\.preview).count, verified)
    XCTAssertTrue(
      try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Jobs").path)
        .isEmpty)
  }
  private func seconds(_ duration: Duration) -> Double {
    let c = duration.components
    return Double(c.seconds) + Double(c.attoseconds) / 1e18
  }
}

@MainActor
private final class BenchmarkSession: SiteSessionStoring {
  func hasSavedCookies(for source: URL) async -> Bool { false }
  func exportCookieFile(for source: URL, to directory: URL) async throws -> URL? { nil }
  func clear(for source: URL) async {}
}
