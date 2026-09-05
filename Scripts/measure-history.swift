import Foundation

// Compile with the EucranteCore sources using swiftc -O -parse-as-library.
// Every read/write is confined to a fresh temporary directory.
@main
enum HistoryMeasurement {
  static func main() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eucrante-history-measurement-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("jobs.json")
    let store = JobStore(fileURL: file)
    let date = Date(timeIntervalSince1970: 1_750_000_000)
    var jobs = (0..<2_000).map { index in
      PersistentJob(
        sourceURL: URL(string: "https://example.com/media/\(index)")!, preset: .appleMusicBest,
        state: .completed, bytesCompleted: 12_000_000, filename: "Sample \(index).m4a",
        outputPath: "/fixture/Sample \(index).m4a", mediaDecision: .passthrough,
        mediaMetadata: MediaMetadata(title: "Sample \(index)", artist: "Fixture Artist"),
        createdAt: date, updatedAt: date)
    }
    try store.save(jobs)
    let clock = ContinuousClock()
    let changed = try clock.measure {
      for index in 0..<20 {
        jobs[index].importedToMusic = true
        try store.save(jobs)
      }
    }
    let unchanged = try clock.measure {
      for _ in 0..<20 { try store.save(jobs) }
    }
    guard try store.load() == jobs else { fatalError("History round trip failed") }
    print("jobs=\(jobs.count) bytes=\(try Data(contentsOf: file).count)")
    print("20 changed saves: \(changed)")
    print("20 unchanged saves: \(unchanged)")
  }
}
