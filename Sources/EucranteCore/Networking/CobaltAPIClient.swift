import Foundation

public protocol MediaProcessingEngine: Sendable {
  func instanceInfo() async throws -> CobaltInstanceInfo
  func process(_ request: CobaltRequest) async throws -> CobaltResponse
}

public enum CobaltAuthentication: Equatable, Sendable {
  case none
  case apiKey(String)
  case bearer(String)

  var authorizationHeader: String? {
    switch self {
    case .none: nil
    case .apiKey(let value): "Api-Key \(value)"
    case .bearer(let value): "Bearer \(value)"
    }
  }
}

public struct CobaltAPIClient: MediaProcessingEngine, Sendable {
  private static let maximumResponseBytes = 2 * 1_024 * 1_024

  private let baseURL: URL
  private let authentication: CobaltAuthentication
  private let session: URLSession
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(
    baseURL: URL,
    authentication: CobaltAuthentication = .none,
    session: URLSession = .shared
  ) {
    self.baseURL = baseURL
    self.authentication = authentication
    self.session = session
    encoder = JSONEncoder()
    decoder = JSONDecoder()
  }

  public func instanceInfo() async throws -> CobaltInstanceInfo {
    guard EndpointSecurityPolicy.allowsConnection(to: endpointURL) else {
      throw CobaltClientError.insecureEndpoint
    }
    var request = URLRequest(url: endpointURL)
    request.httpMethod = "GET"
    request.timeoutInterval = 15
    try applyAuthentication(to: &request)
    let (data, response) = try await session.data(
      for: request,
      delegate: RejectingRedirectDelegate.shared
    )
    try validate(response)
    try validateResponseSize(data)
    return try decode(CobaltInstanceInfo.self, from: data)
  }

  public func process(_ cobaltRequest: CobaltRequest) async throws -> CobaltResponse {
    guard EndpointSecurityPolicy.allowsConnection(to: endpointURL) else {
      throw CobaltClientError.insecureEndpoint
    }
    var request = URLRequest(url: endpointURL)
    request.httpMethod = "POST"
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    try applyAuthentication(to: &request)

    do {
      request.httpBody = try encoder.encode(cobaltRequest)
    } catch {
      throw CobaltClientError.encoding(error.localizedDescription)
    }

    let (data, response) = try await session.data(
      for: request,
      delegate: RejectingRedirectDelegate.shared
    )
    try validate(response)
    try validateResponseSize(data)
    return try decode(CobaltResponse.self, from: data)
  }

  private var endpointURL: URL {
    guard !baseURL.path.isEmpty, baseURL.path != "/" else { return baseURL }
    return baseURL.appendingPathComponent("")
  }

  private func applyAuthentication(to request: inout URLRequest) throws {
    if let header = authentication.authorizationHeader {
      guard EndpointSecurityPolicy.allowsCredentials(to: request.url ?? baseURL) else {
        throw CobaltClientError.insecureAuthenticationEndpoint
      }
      request.setValue(header, forHTTPHeaderField: "Authorization")
    }
  }

  private func validate(_ response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse else {
      throw CobaltClientError.invalidResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      throw CobaltClientError.httpStatus(http.statusCode)
    }
  }

  private func validateResponseSize(_ data: Data) throws {
    guard data.count <= Self.maximumResponseBytes else {
      throw CobaltClientError.responseTooLarge
    }
  }

  private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    do {
      return try decoder.decode(type, from: data)
    } catch {
      throw CobaltClientError.decoding(error.localizedDescription)
    }
  }
}

private final class RejectingRedirectDelegate: NSObject, URLSessionTaskDelegate,
  @unchecked Sendable
{
  static let shared = RejectingRedirectDelegate()

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

public enum CobaltClientError: LocalizedError, Equatable, Sendable {
  case invalidResponse
  case insecureEndpoint
  case insecureAuthenticationEndpoint
  case responseTooLarge
  case httpStatus(Int)
  case encoding(String)
  case decoding(String)

  public var errorDescription: String? {
    switch self {
    case .invalidResponse:
      "The processing instance returned an invalid response."
    case .insecureEndpoint:
      "Public processing endpoints must use HTTPS."
    case .insecureAuthenticationEndpoint:
      "API credentials require HTTPS, except when connecting to this Mac."
    case .responseTooLarge:
      "The processing instance returned an unexpectedly large API response."
    case .httpStatus(let code):
      "The processing instance returned HTTP \(code)."
    case .encoding:
      "The save request could not be created."
    case .decoding:
      "The processing instance returned an unsupported response."
    }
  }
}
