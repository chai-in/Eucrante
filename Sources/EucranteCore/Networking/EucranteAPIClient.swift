import Foundation

public struct EucranteAPIClient: Sendable {
  private static let maximumResponseBytes = 2 * 1_024 * 1_024

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

  private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
    let (data, response) = try await session.data(
      for: request,
      delegate: RejectingEucranteRedirectDelegate.shared
    )
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

  private func url(path: String) throws -> URL {
    guard EndpointSecurityPolicy.allowsConnection(to: baseURL) else {
      throw EucranteClientError.insecureEndpoint
    }
    return baseURL.appendingPathComponent(path)
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
    }
  }
}
