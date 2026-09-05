@preconcurrency import AVFoundation
import Foundation

// Compile with EucranteCore using swiftc -O -parse-as-library. Pass a disposable directory
// and "create", "before", or "after". Fixture creation is excluded from export measurements.
@main
enum MediaMeasurement {
  static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let mode = CommandLine.arguments[2]
    let video = root.appendingPathComponent("video.mp4")
    let audio = root.appendingPathComponent("audio.m4a")
    if mode == "create" {
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      try await makeVideo(at: video)
      let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100 * 8)!
      buffer.frameLength = buffer.frameCapacity
      for channel in 0..<2 {
        for frame in 0..<Int(buffer.frameLength) {
          buffer.floatChannelData![channel][frame] = Float(
            sin(Double(frame) * 2 * .pi * 440 / 44_100) * 0.1)
        }
      }
      let writer = try AVAudioFile(
        forWriting: audio,
        settings: [
          AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
          AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000,
        ])
      try writer.write(from: buffer)
      return
    }
    let processor = LocalMediaProcessor()
    for run in 0..<3 {
      let destination = root.appendingPathComponent("\(mode)-\(run)")
      try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: destination) }
      let start = ContinuousClock.now
      let processed: ProcessedMedia
      let intermediateBytes: Int
      if mode == "before" {
        let merged = try await processor.merge(
          video: video, audio: audio, filename: "merged.mp4", workingDirectory: destination)
        intermediateBytes = try merged.resourceValues(forKeys: [.fileSizeKey]).fileSize!
        processed = try await processor.process(
          merged, preset: .appleVideoEfficient, suggestedFilename: "saved.mp4",
          destination: destination)
      } else {
        intermediateBytes = 0
        processed = try await processor.process(
          video: video, audio: audio, preset: .appleVideoEfficient,
          suggestedFilename: "saved.mp4", destination: destination)
      }
      precondition(processed.output.videoCodec == "hvc1" && processed.output.audioCodec != nil)
      precondition(processed.output.width == 1920 && processed.output.height == 1080)
      precondition(abs(processed.output.duration - 8) < 0.1)
      print(
        "\(mode) run=\(run) time=\(start.duration(to: .now)) intermediate=\(intermediateBytes) output=\(processed.output.fileSize)"
      )
    }
  }

  private static func makeVideo(at url: URL) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1920, AVVideoHeightKey: 1080,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000],
      ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input)
    writer.add(input)
    guard writer.startWriting() else { throw writer.error! }
    writer.startSession(atSourceTime: .zero)
    let buffers = (0..<2).map { seed -> CVPixelBuffer in
      var pixelBuffer: CVPixelBuffer?
      precondition(
        CVPixelBufferCreate(
          kCFAllocatorDefault, 1920, 1080, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
          == kCVReturnSuccess)
      let buffer = pixelBuffer!
      CVPixelBufferLockBaseAddress(buffer, [])
      let pixels = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt32.self)
      var random = UInt32(seed + 1)
      for pixel in 0..<(CVPixelBufferGetDataSize(buffer) / 4) {
        random = random &* 1_664_525 &+ 1_013_904_223
        pixels[pixel] = random | 0xFF00_0000
      }
      CVPixelBufferUnlockBaseAddress(buffer, [])
      return buffer
    }
    for frame in 0..<240 {
      while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(1)) }
      guard
        adaptor.append(
          buffers[frame % 2], withPresentationTime: CMTime(value: Int64(frame), timescale: 30))
      else { throw writer.error! }
    }
    input.markAsFinished()
    await withCheckedContinuation { continuation in
      writer.finishWriting { continuation.resume() }
    }
    guard writer.status == .completed else { throw writer.error! }
  }
}
