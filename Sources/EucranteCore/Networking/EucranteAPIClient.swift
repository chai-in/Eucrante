import Foundation

public struct EucranteAPIClient: Sendable {
  private static let maximumResponseBytes = 2 * 1_024 * 1_024
  private static let multipartPartSize = 8 * 1_024 * 1_024

  private let baseURL: URL
  private let access: CloudflareAccessCredentials?
  private let session: URLSession
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  public init(
    baseURL: URL,
    access: CloudflareAccessCredentials? = nil,
    session: URLSession = .shared
  ) {
    self.baseURL = baseURL
    self.access = access
    self.session = session
  }

  public func discovery() async throws -> EucranteDiscovery {
    let endpoint = try url(path: ".well-known/eucrante")
    var request = URLRequest(url: endpoint)
    request.httpMethod = "GET"
    request.timeoutInterval = 15
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    try applyAccess(to: &request)
    return try await send(request, as: EucranteDiscovery.self)
  }

  public func createJob(
    request cobaltRequest: CobaltRequest,
    preset: EucrantePreset = .custom
  ) async throws -> EucranteJobResult {
    let endpoint = try url(path: "v1/jobs")
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = 60
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    try applyAccess(to: &request)

    do {
      request.httpBody = try encoder.encode(
        CreateJobRequest(request: cobaltRequest, preset: preset))
    } catch {
      throw EucranteClientError.encoding
    }
    return try await send(request, as: EucranteJobResult.self)
  }

  public func job(id: UUID) async throws -> EucranteJobManifest {
    let endpoint = try url(path: "v1/jobs/\(id.uuidString.lowercased())")
    var request = URLRequest(url: endpoint)
    request.httpMethod = "GET"
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    try applyAccess(to: &request)
    return try await send(request, as: EucranteJobEnvelope.self).job
  }

  public func deleteJob(id: UUID) async throws -> EucranteDeleteResult {
    let endpoint = try url(path: "v1/jobs/\(id.uuidString.lowercased())")
    var request = URLRequest(url: endpoint)
    request.httpMethod = "DELETE"
    request.timeoutInterval = 60
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    try applyAccess(to: &request)
    return try await send(request, as: EucranteDeleteResult.self)
  }

  public func uploadOutput(
    jobID: UUID,
    fileURL: URL,
    slot: String,
    contentType: String = "application/octet-stream",
    resumeState: EucranteMultipartState? = nil,
    progress: @escaping @Sendable (EucranteMultipartState?) -> Void = { _ in }
  ) async throws -> EucranteArtifactResult {
    let values: URLResourceValues
    do {
      values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    } catch {
      throw EucranteClientError.fileAccess
    }
    guard values.isRegularFile == true, let rawSize = values.fileSize, rawSize > 0 else {
      throw EucranteClientError.fileAccess
    }
    let fileSize = Int64(rawSize)
    if fileSize <= Int64(Self.multipartPartSize) {
      let result = try await uploadOutputDirect(
        jobID: jobID,
        fileURL: fileURL,
        slot: slot,
        contentType: contentType
      )
      progress(nil)
      return result
    }
    return try await uploadOutputMultipart(
      jobID: jobID,
      fileURL: fileURL,
      fileSize: fileSize,
      slot: slot,
      contentType: contentType,
      resumeState: resumeState,
      progress: progress
    )
  }

  private func uploadOutputDirect(
    jobID: UUID,
    fileURL: URL,
    slot: String,
    contentType: String
  ) async throws -> EucranteArtifactResult {
    let safeSlot = FilenameSanitizer.sanitize(slot, maximumLength: 64)
    let endpoint = try url(
      path: "v1/jobs/\(jobID.uuidString.lowercased())/outputs/\(safeSlot)"
    )
    var request = URLRequest(url: endpoint)
    request.httpMethod = "PUT"
    request.timeoutInterval = 24 * 60 * 60
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    try applyAccess(to: &request)

    let (data, response) = try await session.upload(
      for: request,
      fromFile: fileURL,
      delegate: RejectingEucranteRedirectDelegate.shared
    )
    return try decodeResponse(data: data, response: response, as: EucranteArtifactResult.self)
  }

  private func uploadOutputMultipart(
    jobID: UUID,
    fileURL: URL,
    fileSize: Int64,
    slot: String,
    contentType: String,
    resumeState: EucranteMultipartState?,
    progress: @escaping @Sendable (EucranteMultipartState?) -> Void
  ) async throws -> EucranteArtifactResult {
    let safeSlot = FilenameSanitizer.sanitize(slot, maximumLength: 64)
    let partSize = Self.multipartPartSize
    let totalParts = Int((fileSize + Int64(partSize) - 1) / Int64(partSize))
    let resumePartNumbers = Set(resumeState?.parts.map(\.partNumber) ?? [])
    let resumeIsValid =
      resumeState?.fileSize == fileSize
      && resumeState?.partSize == partSize
      && resumePartNumbers.count == resumeState?.parts.count
      && resumePartNumbers.allSatisfy { (1...totalParts).contains($0) }
    var state: EucranteMultipartState
    if let resumeState, resumeIsValid {
      state = resumeState
    } else {
      if let resumeState {
        try? await abortMultipart(
          jobID: jobID,
          slot: safeSlot,
          uploadID: resumeState.uploadID
        )
      }
      let started = try await startMultipart(
        jobID: jobID,
        slot: safeSlot,
        contentType: contentType
      )
      state = EucranteMultipartState(
        uploadID: started.uploadId,
        fileSize: fileSize,
        partSize: partSize
      )
      progress(state)
    }

    let existingPartNumbers = Set(state.parts.map(\.partNumber))
    let handle: FileHandle
    do {
      handle = try FileHandle(forReadingFrom: fileURL)
    } catch {
      throw EucranteClientError.fileAccess
    }
    defer { try? handle.close() }

    for partNumber in 1...totalParts {
      try Task.checkCancellation()
      if existingPartNumbers.contains(partNumber) { continue }
      let offset = Int64(partNumber - 1) * Int64(partSize)
      do {
        try handle.seek(toOffset: UInt64(offset))
      } catch {
        throw EucranteClientError.fileAccess
      }
      let remaining = fileSize - offset
      let length = Int(min(Int64(partSize), remaining))
      let data: Data
      do {
        data = try handle.read(upToCount: length) ?? Data()
      } catch {
        throw EucranteClientError.fileAccess
      }
      guard data.count == length else { throw EucranteClientError.fileAccess }

      let completed = try await uploadPart(
        jobID: jobID,
        slot: safeSlot,
        uploadID: state.uploadID,
        partNumber: partNumber,
        data: data,
        contentType: contentType
      )
      state.parts.append(completed)
      state.parts.sort { $0.partNumber < $1.partNumber }
      state.bytesCompleted = completedBytes(
        parts: state.parts,
        fileSize: fileSize,
        partSize: partSize
      )
      progress(state)
    }

    let result = try await completeMultipart(
      jobID: jobID,
      slot: safeSlot,
      uploadID: state.uploadID,
      parts: state.parts
    )
    progress(nil)
    return result
  }

  private func startMultipart(
    jobID: UUID,
    slot: String,
    contentType: String
  ) async throws -> EucranteMultipartStart {
    let endpoint = try url(
      path: "v1/jobs/\(jobID.uuidString.lowercased())/outputs/\(slot)/multipart")
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = 60
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    try applyAccess(to: &request)
    return try await send(request, as: EucranteMultipartStart.self)
  }

  private func uploadPart(
    jobID: UUID,
    slot: String,
    uploadID: String,
    partNumber: Int,
    data: Data,
    contentType: String
  ) async throws -> EucranteMultipartPart {
    let endpoint = try url(
      path:
        "v1/jobs/\(jobID.uuidString.lowercased())/outputs/\(slot)/multipart/parts/\(partNumber)",
      queryItems: [URLQueryItem(name: "uploadId", value: uploadID)]
    )
    var request = URLRequest(url: endpoint)
    request.httpMethod = "PUT"
    request.timeoutInterval = 15 * 60
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    try applyAccess(to: &request)
    let (responseData, response) = try await session.upload(
      for: request,
      from: data,
      delegate: RejectingEucranteRedirectDelegate.shared
    )
    return try decodeResponse(
      data: responseData,
      response: response,
      as: EucranteMultipartPart.self
    )
  }

  private func completeMultipart(
    jobID: UUID,
    slot: String,
    uploadID: String,
    parts: [EucranteMultipartPart]
  ) async throws -> EucranteArtifactResult {
    let endpoint = try url(
      path: "v1/jobs/\(jobID.uuidString.lowercased())/outputs/\(slot)/multipart/complete")
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = 15 * 60
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    try applyAccess(to: &request)
    do {
      request.httpBody = try encoder.encode(
        CompleteMultipartRequest(uploadId: uploadID, parts: parts))
    } catch {
      throw EucranteClientError.encoding
    }
    return try await send(request, as: EucranteArtifactResult.self)
  }

  private func abortMultipart(jobID: UUID, slot: String, uploadID: String) async throws {
    let endpoint = try url(
      path: "v1/jobs/\(jobID.uuidString.lowercased())/outputs/\(slot)/multipart/abort",
      queryItems: [URLQueryItem(name: "uploadId", value: uploadID)]
    )
    var request = URLRequest(url: endpoint)
    request.httpMethod = "DELETE"
    request.timeoutInterval = 60
    try applyAccess(to: &request)
    let (data, response) = try await session.data(
      for: request,
      delegate: RejectingEucranteRedirectDelegate.shared
    )
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
      data.count <= Self.maximumResponseBytes
    else {
      throw EucranteClientError.invalidResponse
    }
  }

  private func completedBytes(
    parts: [EucranteMultipartPart],
    fileSize: Int64,
    partSize: Int
  ) -> Int64 {
    parts.reduce(into: 0) { total, part in
      let offset = Int64(part.partNumber - 1) * Int64(partSize)
      total += max(0, min(Int64(partSize), fileSize - offset))
    }
  }

  private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
    let (data, response) = try await session.data(
      for: request,
      delegate: RejectingEucranteRedirectDelegate.shared
    )
    return try decodeResponse(data: data, response: response, as: type)
  }

  private func decodeResponse<T: Decodable>(
    data: Data,
    response: URLResponse,
    as type: T.Type
  ) throws -> T {
    guard let http = response as? HTTPURLResponse else {
      throw EucranteClientError.invalidResponse
    }
    guard data.count <= Self.maximumResponseBytes else {
      throw EucranteClientError.responseTooLarge
    }
    guard (200..<300).contains(http.statusCode) else {
      if http.statusCode == 401 || http.statusCode == 403 {
        throw EucranteClientError.accessDenied
      }
      throw EucranteClientError.httpStatus(http.statusCode)
    }
    do {
      return try decoder.decode(type, from: data)
    } catch {
      throw EucranteClientError.decoding
    }
  }

  private func url(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
    guard EndpointSecurityPolicy.allowsConnection(to: baseURL) else {
      throw EucranteClientError.insecureEndpoint
    }
    let endpoint = baseURL.appendingPathComponent(path)
    guard !queryItems.isEmpty else { return endpoint }
    guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
      throw EucranteClientError.invalidResponse
    }
    components.queryItems = queryItems
    guard let result = components.url else { throw EucranteClientError.invalidResponse }
    return result
  }

  private func applyAccess(to request: inout URLRequest) throws {
    guard let access else { return }
    guard EndpointSecurityPolicy.allowsCredentials(to: request.url ?? baseURL) else {
      throw EucranteClientError.insecureEndpoint
    }
    request.setValue(access.clientID, forHTTPHeaderField: "CF-Access-Client-Id")
    request.setValue(access.clientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
  }
}

private struct CreateJobRequest: Encodable {
  let request: CobaltRequest
  let preset: EucrantePreset
}

private struct CompleteMultipartRequest: Encodable {
  let uploadId: String
  let parts: [EucranteMultipartPart]
}

private final class RejectingEucranteRedirectDelegate: NSObject, URLSessionTaskDelegate,
  @unchecked Sendable
{
  static let shared = RejectingEucranteRedirectDelegate()

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

public enum EucranteClientError: LocalizedError, Equatable, Sendable {
  case invalidResponse
  case insecureEndpoint
  case responseTooLarge
  case accessDenied
  case httpStatus(Int)
  case encoding
  case decoding
  case fileAccess

  public var errorDescription: String? {
    switch self {
    case .invalidResponse:
      "The Eucrante deployment returned an invalid response."
    case .insecureEndpoint:
      "Public Eucrante deployments must use HTTPS."
    case .responseTooLarge:
      "The Eucrante deployment returned an unexpectedly large response."
    case .accessDenied:
      "Cloudflare Access denied this Mac. Check the service token and WARP connection."
    case .httpStatus(let code):
      "The Eucrante deployment returned HTTP \(code)."
    case .encoding:
      "The save request could not be created."
    case .decoding:
      "The Eucrante deployment returned an unsupported response."
    case .fileAccess:
      "The verified output file could not be read for its retained cloud upload."
    }
  }
}
