@preconcurrency import AVFoundation
import Foundation

public enum AudioLevelAnalyzer {
  public static func musicVolumeAdjustment(for url: URL) async throws -> Int {
    let rmsDB = try await Task.detached(priority: .userInitiated) {
      try await measureRMS(at: url)
    }.value
    return musicVolumeAdjustment(rmsDB: rmsDB)
  }

  public static func musicVolumeAdjustment(rmsDB: Double) -> Int {
    guard rmsDB.isFinite else { return 0 }
    // Music's adjustment is non-destructive. -12 dBFS closely matches a typical
    // mastered library track while the cap avoids extreme gain on quiet recordings.
    let targetRMSDB = -12.0
    let linearGain = pow(10, (targetRMSDB - rmsDB) / 20)
    return min(50, max(-25, Int(((linearGain - 1) * 100).rounded())))
  }

  private static func measureRMS(at url: URL) async throws -> Double {
    let asset = AVURLAsset(url: url)
    let reader = try AVAssetReader(asset: asset)
    guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
      throw AudioLevelError.missingAudio
    }
    let output = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsNonInterleaved: false,
      ]
    )
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { throw AudioLevelError.readerUnavailable }
    reader.add(output)
    guard reader.startReading() else {
      throw reader.error ?? AudioLevelError.readerUnavailable
    }

    var sumSquares = 0.0
    var sampleCount = 0
    while reader.status == .reading, let sample = output.copyNextSampleBuffer() {
      guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
      let byteCount = CMBlockBufferGetDataLength(block)
      guard byteCount >= MemoryLayout<Float>.size else { continue }
      var data = Data(count: byteCount)
      let status = data.withUnsafeMutableBytes { bytes in
        CMBlockBufferCopyDataBytes(
          block,
          atOffset: 0,
          dataLength: byteCount,
          destination: bytes.baseAddress!
        )
      }
      guard status == kCMBlockBufferNoErr else { throw AudioLevelError.readFailed }
      data.withUnsafeBytes { bytes in
        for value in bytes.bindMemory(to: Float.self) {
          let sample = Double(value)
          sumSquares += sample * sample
          sampleCount += 1
        }
      }
    }
    guard reader.status == .completed, sampleCount > 0 else {
      throw reader.error ?? AudioLevelError.readFailed
    }
    let rms = sqrt(sumSquares / Double(sampleCount))
    return 20 * log10(max(rms, Double.leastNonzeroMagnitude))
  }
}

public enum AudioLevelError: LocalizedError, Equatable, Sendable {
  case missingAudio
  case readerUnavailable
  case readFailed

  public var errorDescription: String? {
    switch self {
    case .missingAudio: "The file does not contain an audio track."
    case .readerUnavailable: "The audio level could not be inspected."
    case .readFailed: "The audio level inspection did not finish."
    }
  }
}
