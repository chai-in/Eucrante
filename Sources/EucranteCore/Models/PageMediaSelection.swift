import Foundation

public struct PageMediaSelection: Decodable, Sendable {
  public struct Item: Decodable, Equatable, Identifiable, Sendable {
    public let url: URL
    public let title: String
    public var id: URL { url }
  }
  public let page: URL
  public let title: String
  public let items: [Item]
  public let truncated: Bool

  public static func decode(_ url: URL) throws -> Self {
    guard url.scheme == "eucrante", url.host == "page", url.absoluteString.utf8.count <= 200_000,
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let payload = components.queryItems?.first(where: { $0.name == "payload" })?.value,
      payload.utf8.count <= 65_536,
      let value = try? JSONDecoder().decode(Self.self, from: Data(payload.utf8)),
      !value.items.isEmpty, value.items.count <= 100, value.title.count <= 240,
      (try? SourceURLValidator.validate(value.page.absoluteString)) != nil,
      value.items.allSatisfy({
        $0.title.count <= 240 && (try? SourceURLValidator.validate($0.url.absoluteString)) != nil
      }),
      Set(value.items.map(\.url)).count == value.items.count
    else { throw SourceURLValidationError.invalid }
    return value
  }
}
