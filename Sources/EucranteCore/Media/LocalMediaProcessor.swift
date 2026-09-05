@preconcurrency import AVFoundation
import AudioToolbox
import CoreMedia
import Darwin
import Foundation

public struct MediaFileInfo: Codable, Equatable, Sendable {
  public let duration: Double
  public let fileSize: Int64
  public let audioCodec: String?
  public let audioBitrate: Double?
  public let sampleRate: Double?
  public let channelCount: Int?
  public let videoCodec: String?
  public let videoBitrate: Double?
  public let width: Int?
  public let height: Int?
  public let frameRate: Double?
  public let isHDR: Bool

  public init(
    duration: Double,
    fileSize: Int64,
    audioCodec: String?,
    audioBitrate: Double?,
    sampleRate: Double?,
    channelCount: Int?,
    videoCodec: String?,
    videoBitrate: Double?,
    width: Int?,
    height: Int?,
    frameRate: Double?,
    isHDR: Bool
  ) {
    self.duration = duration
    self.fileSize = fileSize
    self.audioCodec = audioCodec
    self.audioBitrate = audioBitrate
    self.sampleRate = sampleRate
    self.channelCount = channelCount
    self.videoCodec = videoCodec
    self.videoBitrate = videoBitrate
    self.width = width
    self.height = height
    self.frameRate = frameRate
    self.isHDR = isHDR
  }
}

public struct ProcessedMedia: Equatable, Sendable {
  public let url: URL
  public let decision: MediaDecision
  public let source: MediaFileInfo
  public let output: MediaFileInfo

  public init(url: URL, decision: MediaDecision, source: MediaFileInfo, output: MediaFileInfo) {
    self.url = url
    self.decision = decision
    self.source = source
    self.output = output
  }
}

public protocol MediaProcessing: Sendable {
  func inspect(_ url: URL) async throws -> MediaFileInfo
  func process(
    _ input: URL,
    preset: EucrantePreset,
    suggestedFilename: String?,
    destination: URL,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> ProcessedMedia
}

public actor LocalMediaProcessor: MediaProcessing {
  private let fileManager: FileManager
  private var reservedDestinationPaths: Set<String> = []

  public init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  public func inspect(_ url: URL) async throws -> MediaFileInfo {
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
    return try await inspect(AVURLAsset(url: url), fileSize: size)
  }

  private func inspect(_ asset: AVAsset, fileSize: Int64) async throws -> MediaFileInfo {
    let duration = try await asset.load(.duration).seconds
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    let videoTracks = try await asset.loadTracks(withMediaType: .video)
    let audio = audioTracks.first
    let video = videoTracks.first
    let audioDescription = try await audio?.load(.formatDescriptions).first
    let videoDescription = try await video?.load(.formatDescriptions).first
    let audioBasic = audioDescription.flatMap {
      CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee
    }
    let naturalSize = try await video?.load(.naturalSize)
    let transformedSize: CGSize? =
      if let video, let naturalSize {
        absSize(naturalSize.applying(try await video.load(.preferredTransform)))
      } else {
        nil
      }
    let nominalFrameRate: Double? =
      if let video {
        Double(try await video.load(.nominalFrameRate))
      } else {
        nil
      }
    let audioCodec = audioDescription.map(codecName)
    let videoCodec = videoDescription.map(codecName)
    let audioBitrate: Double? =
      if let audio {
        Double(try await audio.load(.estimatedDataRate))
      } else {
        nil
      }
    let videoBitrate: Double? =
      if let video {
        Double(try await video.load(.estimatedDataRate))
      } else {
        nil
      }
    let width = transformedSize.map { Int($0.width.rounded()) }
    let height = transformedSize.map { Int($0.height.rounded()) }
    let hdr = videoDescription.map(isHDRFormat) ?? false

    return MediaFileInfo(
      duration: duration.isFinite ? max(0, duration) : 0,
      fileSize: fileSize,
      audioCodec: audioCodec,
      audioBitrate: audioBitrate,
      sampleRate: audioBasic?.mSampleRate,
      channelCount: audioBasic.map { Int($0.mChannelsPerFrame) },
      videoCodec: videoCodec,
      videoBitrate: videoBitrate,
      width: width,
      height: height,
      frameRate: nominalFrameRate,
      isHDR: hdr
    )
  }

  public func process(
    _ input: URL,
    preset: EucrantePreset,
    suggestedFilename: String?,
    destination: URL,
    progress: @escaping @Sendable (Double) -> Void = { _ in }
  ) async throws -> ProcessedMedia {
    try Task.checkCancellation()
    let staging = try makeStaging(in: destination)
    defer { try? fileManager.removeItem(at: staging) }

    let processed = try await processInStaging(
      input, preset: preset, suggestedFilename: suggestedFilename,
      destination: staging, progress: progress)
    return try publish(processed, to: destination)
  }

  // Compose acquired tracks directly into the destination's private staging directory.
  // In particular, Efficient no longer writes a full H.264 merge before encoding HEVC.
  public func process(
    video: URL, audio: URL, preset: EucrantePreset, suggestedFilename: String,
    destination: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }
  ) async throws -> ProcessedMedia {
    try Task.checkCancellation()
    guard !preset.isAudio else { throw MediaProcessingError.unsupportedOutput }
    let staging = try makeStaging(in: destination)
    defer { try? fileManager.removeItem(at: staging) }
    let composition = try await composition(video: video, audio: audio)
    let size = [video, audio].reduce(Int64(0)) {
      $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
    let source = try await inspect(composition, fileSize: size)
    let name = outputName(suggestedFilename, extension: "mp4")
    let decision = Self.decision(for: URL(fileURLWithPath: name), preset: preset, info: source)
    let outputURL = try await exportAsset(
      composition,
      presetName: decision == .transcodeHEVC
        ? Self.hevcPreset(for: source) : AVAssetExportPresetPassthrough,
      fileType: .mp4, filename: name, destination: staging, progress: progress)
    try Task.checkCancellation()
    let output = try await inspect(outputURL)
    try Self.verify(source: source, output: output, preset: preset, decision: decision)
    guard output.audioCodec != nil, output.videoCodec != nil else {
      throw MediaProcessingError.verification("The merged output is missing a requested track.")
    }
    progress(1)
    return try publish(
      ProcessedMedia(url: outputURL, decision: decision, source: source, output: output),
      to: destination)
  }

  private func makeStaging(in destination: URL) throws -> URL {
    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
    let staging = destination.appendingPathComponent(
      ".eucrante-\(UUID().uuidString)", isDirectory: true)
    try SecureCredentialFile.prepareDirectory(staging, fileManager: fileManager)
    return staging
  }

  private func publish(_ processed: ProcessedMedia, to destination: URL) throws -> ProcessedMedia {
    try Task.checkCancellation()
    let output = reserveDestination(for: processed.url.lastPathComponent, in: destination)
    defer { releaseDestination(output) }
    // Same-volume publication happens only after verification and never replaces an existing file.
    do {
      try fileManager.moveItem(at: processed.url, to: output)
    } catch {
      throw MediaProcessingError.file(error.localizedDescription)
    }
    return ProcessedMedia(
      url: output, decision: processed.decision, source: processed.source, output: processed.output)
  }

  private func processInStaging(
    _ input: URL,
    preset: EucrantePreset,
    suggestedFilename: String?,
    destination: URL,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> ProcessedMedia {
    guard preset != .custom else {
      let source = try await inspect(input)
      try Self.verify(source: source, output: source, preset: .custom, decision: .passthrough)
      try Task.checkCancellation()
      let outputURL = try copy(
        input,
        named: suggestedFilename ?? input.lastPathComponent,
        to: destination
      )
      let output = try await inspect(outputURL)
      try Self.verify(source: source, output: output, preset: .custom, decision: .passthrough)
      return ProcessedMedia(url: outputURL, decision: .passthrough, source: source, output: output)
    }

    try Task.checkCancellation()
    let source = try await inspect(input)
    let decision = Self.decision(for: input, preset: preset, info: source)
    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
    progress(0)

    let outputURL: URL
    switch decision {
    case .passthrough:
      outputURL = try copy(
        input,
        named: suggestedFilename ?? input.lastPathComponent,
        to: destination
      )
      progress(1)
    case .remux:
      outputURL = try await export(
        input,
        presetName: AVAssetExportPresetPassthrough,
        fileType: preset.isAudio ? .m4a : .mp4,
        filename: outputName(
          suggestedFilename ?? input.lastPathComponent, extension: preset.isAudio ? "m4a" : "mp4"),
        destination: destination,
        progress: progress
      )
    case .transcodeAAC:
      outputURL = try await export(
        input,
        presetName: AVAssetExportPresetAppleM4A,
        fileType: .m4a,
        filename: outputName(suggestedFilename ?? input.lastPathComponent, extension: "m4a"),
        destination: destination,
        progress: progress
      )
    case .transcodeALAC:
      outputURL = try await transcodeAudio(
        input,
        formatID: kAudioFormatAppleLossless,
        bitrate: nil,
        filename: outputName(suggestedFilename ?? input.lastPathComponent, extension: "m4a"),
        destination: destination,
        progress: progress
      )
    case .transcodeHEVC:
      let exportPreset = Self.hevcPreset(for: source)
      outputURL = try await export(
        input,
        presetName: exportPreset,
        fileType: .mp4,
        filename: outputName(suggestedFilename ?? input.lastPathComponent, extension: "mp4"),
        destination: destination,
        progress: progress
      )
    }

    try Task.checkCancellation()
    let output = try await inspect(outputURL)
    try Self.verify(source: source, output: output, preset: preset, decision: decision)
    progress(1)
    return ProcessedMedia(url: outputURL, decision: decision, source: source, output: output)
  }

  public func merge(
    video: URL,
    audio: URL,
    filename: String,
    workingDirectory: URL
  ) async throws -> URL {
    let composition = try await composition(video: video, audio: audio)
    return try await exportAsset(
      composition,
      presetName: AVAssetExportPresetPassthrough,
      fileType: .mp4,
      filename: outputName(filename, extension: "mp4"),
      destination: workingDirectory,
      progress: { _ in }
    )
  }

  private func composition(video: URL, audio: URL) async throws -> AVMutableComposition {
    let videoAsset = AVURLAsset(url: video)
    let audioAsset = AVURLAsset(url: audio)
    guard let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video).first,
      let sourceAudio = try await audioAsset.loadTracks(withMediaType: .audio).first
    else {
      throw MediaProcessingError.missingInput
    }
    let composition = AVMutableComposition()
    guard
      let videoTrack = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid
      ),
      let audioTrack = composition.addMutableTrack(
        withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid
      )
    else {
      throw MediaProcessingError.writer
    }
    let videoDuration = try await videoAsset.load(.duration)
    let audioDuration = try await audioAsset.load(.duration)
    let duration = CMTimeMinimum(videoDuration, audioDuration)
    try videoTrack.insertTimeRange(
      CMTimeRange(start: .zero, duration: duration),
      of: sourceVideo,
      at: .zero
    )
    try audioTrack.insertTimeRange(
      CMTimeRange(start: .zero, duration: duration),
      of: sourceAudio,
      at: .zero
    )
    videoTrack.preferredTransform = try await sourceVideo.load(.preferredTransform)
    return composition
  }

  static func decision(
    for input: URL,
    preset: EucrantePreset,
    info: MediaFileInfo
  ) -> MediaDecision {
    let ext = input.pathExtension.lowercased()
    let audioCodec = info.audioCodec?.lowercased()
    let videoCodec = info.videoCodec?.lowercased()

    switch preset {
    case .appleMusicBest:
      if ["m4a", "mp3", "aac", "aif", "aiff", "wav"].contains(ext) { return .passthrough }
      if isLossless(audioCodec) { return .transcodeALAC }
      return .transcodeAAC
    case .appleMusicEfficient:
      if ["aac ", "aac", "mp4a"].contains(audioCodec ?? ""),
        ["m4a", "mp4", "aac"].contains(ext),
        (info.audioBitrate ?? 0) <= 280_000
      {
        return .passthrough
      }
      return .transcodeAAC
    case .appleVideoBest:
      if ["avc1", "avc3", "hvc1", "hev1"].contains(videoCodec ?? ""),
        ["mp4", "m4v", "mov"].contains(ext)
      {
        return .passthrough
      }
      return .transcodeHEVC
    case .appleVideoEfficient:
      if ["hvc1", "hev1"].contains(videoCodec ?? ""),
        (info.videoBitrate ?? .greatestFiniteMagnitude) <= efficientVideoBitrate(info) * 1.15,
        ["mp4", "m4v", "mov"].contains(ext)
      {
        return .passthrough
      }
      return .transcodeHEVC
    case .custom:
      return .passthrough
    }
  }

  private func copy(_ input: URL, named name: String, to destination: URL) throws -> URL {
    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
    let safe = FilenameSanitizer.sanitize(name)
    let output = reserveDestination(for: safe, in: destination)
    defer { releaseDestination(output) }
    do {
      // APFS clones share media blocks until either copy changes. Other volumes use a normal copy.
      if clonefile(input.path, output.path, 0) != 0 {
        try fileManager.copyItem(at: input, to: output)
      }
      return output
    } catch {
      throw MediaProcessingError.file(error.localizedDescription)
    }
  }

  private func export(
    _ input: URL,
    presetName: String,
    fileType: AVFileType,
    filename: String,
    destination: URL,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> URL {
    try await exportAsset(
      AVURLAsset(url: input),
      presetName: presetName,
      fileType: fileType,
      filename: filename,
      destination: destination,
      progress: progress
    )
  }

  private func exportAsset(
    _ asset: AVAsset,
    presetName: String,
    fileType: AVFileType,
    filename: String,
    destination: URL,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> URL {
    guard let exporter = AVAssetExportSession(asset: asset, presetName: presetName) else {
      throw MediaProcessingError.exportUnavailable
    }
    guard exporter.supportedFileTypes.contains(fileType) else {
      throw MediaProcessingError.unsupportedOutput
    }
    let output = reserveDestination(
      for: FilenameSanitizer.sanitize(filename),
      in: destination
    )
    defer { releaseDestination(output) }
    var completed = false
    defer { if !completed { try? fileManager.removeItem(at: output) } }
    exporter.outputURL = output
    exporter.outputFileType = fileType
    exporter.shouldOptimizeForNetworkUse = true
    exporter.metadataItemFilter = .forSharing()
    let cancellableExporter = CancellableExportSession(exporter)

    progress(0.05)
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        cancellableExporter.export { continuation.resume() }
      }
    } onCancel: {
      cancellableExporter.cancel()
    }
    try Task.checkCancellation()

    guard exporter.status == .completed else {
      try? fileManager.removeItem(at: output)
      if Self.isMissingCodec(exporter.error) {
        throw MediaProcessingError.codecUnavailable
      }
      throw MediaProcessingError.export(
        exporter.error?.localizedDescription ?? "Unknown export error")
    }
    completed = true
    return output
  }

  private func transcodeAudio(
    _ input: URL,
    formatID: AudioFormatID,
    bitrate: Int?,
    filename: String,
    destination: URL,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> URL {
    let asset = AVURLAsset(url: input)
    guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
      throw MediaProcessingError.missingAudio
    }
    let duration = try await asset.load(.duration)
    let description = try await track.load(.formatDescriptions).first
    let basic = description.flatMap {
      CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee
    }
    let sampleRate = min(max(basic?.mSampleRate ?? 44_100, 8_000), 48_000)
    let channels = min(max(Int(basic?.mChannelsPerFrame ?? 2), 1), 8)
    let intermediate = FileDestinationResolver.uniqueDestination(
      for: ".eucrante-\(UUID().uuidString).mov",
      in: destination,
      fileManager: fileManager
    )
    let reader = try AVAssetReader(asset: asset)
    let readerOutput = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsNonInterleaved: false,
      ]
    )
    readerOutput.alwaysCopiesSampleData = false
    guard reader.canAdd(readerOutput) else { throw MediaProcessingError.reader }
    reader.add(readerOutput)

    // AVAssetWriter does not accept compressed audio settings for an audio-only
    // M4A container on all supported macOS releases. Encode into a temporary
    // QuickTime container, then losslessly remux the finished track to M4A.
    let writer = try AVAssetWriter(outputURL: intermediate, fileType: .mov)
    var settings: [String: Any] = [
      AVFormatIDKey: formatID,
      AVSampleRateKey: sampleRate,
      AVNumberOfChannelsKey: min(channels, 2),
    ]
    if let bitrate { settings[AVEncoderBitRateKey] = bitrate }
    if formatID == kAudioFormatAppleLossless {
      settings[AVEncoderBitDepthHintKey] = min(max(Int(basic?.mBitsPerChannel ?? 16), 16), 32)
      settings[AVNumberOfChannelsKey] = channels
    }
    let writerInput = AVAssetWriterInput(
      mediaType: .audio,
      outputSettings: settings,
      sourceFormatHint: description
    )
    writerInput.expectsMediaDataInRealTime = false
    guard writer.canAdd(writerInput) else { throw MediaProcessingError.writer }
    writer.add(writerInput)
    writer.metadata = try await asset.load(.commonMetadata)

    guard writer.startWriting() else {
      if Self.isMissingCodec(writer.error) {
        throw MediaProcessingError.codecUnavailable
      }
      throw MediaProcessingError.export(
        writer.error?.localizedDescription ?? "The audio encoder could not start.")
    }
    guard reader.startReading() else {
      writer.cancelWriting()
      throw MediaProcessingError.export(
        reader.error?.localizedDescription ?? "The source audio decoder could not start.")
    }
    writer.startSession(atSourceTime: .zero)

    do {
      while reader.status == .reading {
        try Task.checkCancellation()
        guard writerInput.isReadyForMoreMediaData else {
          try await Task.sleep(for: .milliseconds(10))
          continue
        }
        guard let sample = readerOutput.copyNextSampleBuffer() else { break }
        guard writerInput.append(sample) else {
          throw MediaProcessingError.writer
        }
        let seconds = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        if duration.seconds > 0 { progress(min(0.88, max(0, seconds / duration.seconds * 0.88))) }
      }
      writerInput.markAsFinished()
      await withCheckedContinuation { continuation in
        writer.finishWriting { continuation.resume() }
      }
      guard reader.status == .completed, writer.status == .completed else {
        throw MediaProcessingError.export(
          writer.error?.localizedDescription ?? reader.error?.localizedDescription
            ?? "Audio conversion failed"
        )
      }
      let output = try await exportAsset(
        AVURLAsset(url: intermediate),
        presetName: AVAssetExportPresetPassthrough,
        fileType: .m4a,
        filename: filename,
        destination: destination,
        progress: { value in progress(0.9 + value * 0.1) }
      )
      try? fileManager.removeItem(at: intermediate)
      return output
    } catch {
      reader.cancelReading()
      writer.cancelWriting()
      try? fileManager.removeItem(at: intermediate)
      throw error
    }
  }

  static func verify(
    source: MediaFileInfo,
    output: MediaFileInfo,
    preset: EucrantePreset,
    decision: MediaDecision
  ) throws {
    guard output.fileSize > 0, output.duration > 0 else {
      throw MediaProcessingError.verification("The output is empty or has no playable duration.")
    }
    if preset.isAudio {
      guard output.audioCodec != nil else {
        throw MediaProcessingError.verification("The output does not contain audio.")
      }
      if let sourceRate = source.sampleRate, let outputRate = output.sampleRate,
        outputRate > max(sourceRate, 48_000) + 1
      {
        throw MediaProcessingError.verification("The output sample rate exceeds the source.")
      }
    } else if preset != .custom {
      guard output.videoCodec != nil else {
        throw MediaProcessingError.verification("The output does not contain video.")
      }
      if let sourceWidth = source.width, let outputWidth = output.width,
        outputWidth > sourceWidth + 2
      {
        throw MediaProcessingError.verification("The output width exceeds the source.")
      }
      if let sourceHeight = source.height, let outputHeight = output.height,
        outputHeight > sourceHeight + 2
      {
        throw MediaProcessingError.verification("The output height exceeds the source.")
      }
      if source.isHDR, decision == .transcodeHEVC, !output.isHDR {
        throw MediaProcessingError.verification("HDR metadata was not preserved.")
      }
    }
    guard output.audioCodec != nil || output.videoCodec != nil else {
      throw MediaProcessingError.verification("The output has no playable media tracks.")
    }
    if source.duration > 0, abs(source.duration - output.duration) > max(1, source.duration * 0.02)
    {
      throw MediaProcessingError.verification("The output duration does not match the source.")
    }
  }

  static func hevcPreset(for info: MediaFileInfo) -> String {
    let maxDimension = max(info.width ?? 0, info.height ?? 0)
    if maxDimension <= 1_920 { return AVAssetExportPresetHEVC1920x1080 }
    if maxDimension <= 3_840 { return AVAssetExportPresetHEVC3840x2160 }
    return AVAssetExportPresetHEVCHighestQuality
  }

  static func efficientVideoBitrate(_ info: MediaFileInfo) -> Double {
    let width = Double(info.width ?? 1_920)
    let height = Double(info.height ?? 1_080)
    let fps = max(24, min(info.frameRate ?? 30, 60))
    let bitsPerPixelFrame = info.isHDR ? 0.075 : 0.055
    return min(28_000_000, max(1_600_000, width * height * fps * bitsPerPixelFrame))
  }

  static func isLossless(_ codec: String?) -> Bool {
    guard let codec else { return false }
    return ["alac", "flac", "lpcm", "pcm ", "ape ", "wav "].contains(codec)
  }

  private func outputName(_ source: String, extension ext: String) -> String {
    let stem = URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent
    return "\(stem).\(ext)"
  }

  private func reserveDestination(for filename: String, in directory: URL) -> URL {
    let output = FileDestinationResolver.uniqueDestination(
      for: filename,
      in: directory,
      fileManager: fileManager,
      reservedPaths: reservedDestinationPaths
    )
    reservedDestinationPaths.insert(output.path)
    return output
  }

  private func releaseDestination(_ url: URL) {
    reservedDestinationPaths.remove(url.path)
  }

  private func codecName(_ description: CMFormatDescription) -> String {
    let code = CMFormatDescriptionGetMediaSubType(description)
    let bytes: [UInt8] = [
      UInt8((code >> 24) & 0xff), UInt8((code >> 16) & 0xff),
      UInt8((code >> 8) & 0xff), UInt8(code & 0xff),
    ]
    return String(bytes: bytes, encoding: .macOSRoman) ?? String(code)
  }

  private func isHDRFormat(_ description: CMFormatDescription) -> Bool {
    guard let rawExtensions = CMFormatDescriptionGetExtensions(description) else { return false }
    let extensions = rawExtensions as NSDictionary
    let transfer = extensions[kCMFormatDescriptionExtension_TransferFunction] as? String ?? ""
    return transfer.localizedCaseInsensitiveContains("2084")
      || transfer.localizedCaseInsensitiveContains("HLG")
      || transfer.localizedCaseInsensitiveContains("2100")
  }

  private func absSize(_ size: CGSize) -> CGSize {
    CGSize(width: abs(size.width), height: abs(size.height))
  }

  private static func isMissingCodec(_ error: Error?) -> Bool {
    guard let nsError = error as NSError? else { return false }
    if nsError.code == 1_718_449_215 { return true }  // 'fmt?'
    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
      return underlying.code == 1_718_449_215
    }
    return false
  }
}

private final class CancellableExportSession: @unchecked Sendable {
  private let exporter: AVAssetExportSession

  init(_ exporter: AVAssetExportSession) {
    self.exporter = exporter
  }

  func export(completion: @escaping @Sendable () -> Void) {
    exporter.exportAsynchronously(completionHandler: completion)
  }

  func cancel() {
    exporter.cancelExport()
  }
}

public enum MediaProcessingError: LocalizedError, Equatable, Sendable {
  case missingInput
  case missingAudio
  case exportUnavailable
  case unsupportedOutput
  case codecUnavailable
  case reader
  case writer
  case file(String)
  case export(String)
  case verification(String)
  case unsupportedOperation(String)

  public var errorDescription: String? {
    switch self {
    case .missingInput: "The processing response did not include the required media tracks."
    case .missingAudio: "The downloaded file does not contain an audio track."
    case .exportUnavailable: "This Mac cannot create the selected media output."
    case .unsupportedOutput: "The selected Apple media container is unavailable for this source."
    case .codecUnavailable:
      "This macOS installation does not currently provide the required Apple media encoder. Install the latest macOS update and try again."
    case .reader: "The source media could not be decoded."
    case .writer: "The converted media could not be encoded."
    case .file: "The verified media could not be saved."
    case .export(let message): "Media conversion failed: \(message)"
    case .verification(let message): "Output verification failed: \(message)"
    case .unsupportedOperation(let operation):
      "This result needs an unsupported local operation (\(operation))."
    }
  }
}
