@preconcurrency import AVFoundation
import AudioToolbox
import Foundation

/// Rebuilds a malformed M4A sample table from the original compressed packets.
/// Core Audio counts AAC frames independently of the movie's timeline.
public enum AudioContainerRepair {
  public static func repairIfNeeded(_ input: URL, in directory: URL) async throws -> URL {
    guard input.pathExtension.lowercased() == "m4a" else { return input }
    let file = try AVAudioFile(forReading: input)
    let decodedDuration = Double(file.length) / file.processingFormat.sampleRate
    let movieDuration = try await AVURLAsset(url: input).load(.duration).seconds
    guard decodedDuration.isFinite, decodedDuration > 0, movieDuration.isFinite else {
      throw MediaProcessingError.verification("The audio timing is invalid.")
    }
    guard abs(movieDuration - decodedDuration) > max(1, decodedDuration * 0.02) else {
      return input
    }
    let output = directory.appendingPathComponent("repaired-\(UUID().uuidString).m4a")
    var complete = false
    defer { if !complete { try? FileManager.default.removeItem(at: output) } }
    try copyPackets(input, to: output)
    let corrected = try await AVURLAsset(url: output).load(.duration).seconds
    guard abs(corrected - decodedDuration) <= max(0.1, decodedDuration * 0.001) else {
      throw MediaProcessingError.verification("The audio container could not be repaired.")
    }
    complete = true
    return output
  }

  private static func copyPackets(_ input: URL, to output: URL) throws {
    func check(_ status: OSStatus) throws {
      guard status == noErr else {
        throw MediaProcessingError.verification(
          "The audio packet table could not be rebuilt (\(status)).")
      }
    }
    var source: AudioFileID?
    try check(AudioFileOpenURL(input as CFURL, .readPermission, 0, &source))
    guard let source else { throw MediaProcessingError.reader }
    defer { AudioFileClose(source) }
    var format = AudioStreamBasicDescription()
    var formatSize = UInt32(MemoryLayout.size(ofValue: format))
    try check(AudioFileGetProperty(source, kAudioFilePropertyDataFormat, &formatSize, &format))
    guard format.mFormatID == kAudioFormatMPEG4AAC || format.mFormatID == kAudioFormatAppleLossless
    else {
      throw MediaProcessingError.verification("The audio has an unsupported packet format.")
    }
    var target: AudioFileID?
    try check(AudioFileCreateWithURL(output as CFURL, kAudioFileM4AType, &format, [], &target))
    guard let target else { throw MediaProcessingError.writer }
    defer { AudioFileClose(target) }
    var cookieSize: UInt32 = 0
    if AudioFileGetPropertyInfo(source, kAudioFilePropertyMagicCookieData, &cookieSize, nil)
      == noErr,
      cookieSize > 0, cookieSize <= 1_048_576
    {
      var cookie = [UInt8](repeating: 0, count: Int(cookieSize))
      try check(
        AudioFileGetProperty(source, kAudioFilePropertyMagicCookieData, &cookieSize, &cookie))
      try check(AudioFileSetProperty(target, kAudioFilePropertyMagicCookieData, cookieSize, cookie))
    }
    var maximum: UInt32 = 0
    var size = UInt32(MemoryLayout.size(ofValue: maximum))
    try check(AudioFileGetProperty(source, kAudioFilePropertyPacketSizeUpperBound, &size, &maximum))
    guard maximum > 0, maximum <= 1_048_576 else { throw MediaProcessingError.reader }
    let capacity = max(1, min(512, 1_048_576 / Int(maximum)))
    var bytes = [UInt8](repeating: 0, count: Int(maximum) * capacity)
    var descriptions = [AudioStreamPacketDescription](repeating: .init(), count: capacity)
    var position: Int64 = 0
    while true {
      try Task.checkCancellation()
      var count = UInt32(capacity)
      var byteCount = UInt32(bytes.count)
      let status = AudioFileReadPacketData(
        source, false, &byteCount, &descriptions, position, &count, &bytes)
      guard status == noErr || status == kAudioFileEndOfFileError else {
        try check(status)
        return
      }
      if count == 0 { break }
      let expected = count
      try check(
        AudioFileWritePackets(target, false, byteCount, descriptions, position, &count, bytes))
      guard count == expected else { throw MediaProcessingError.writer }
      position += Int64(count)
    }
    var table = AudioFilePacketTableInfo()
    var tableSize = UInt32(MemoryLayout.size(ofValue: table))
    if AudioFileGetProperty(source, kAudioFilePropertyPacketTableInfo, &tableSize, &table) == noErr
    {
      try check(AudioFileSetProperty(target, kAudioFilePropertyPacketTableInfo, tableSize, &table))
    }
  }
}
