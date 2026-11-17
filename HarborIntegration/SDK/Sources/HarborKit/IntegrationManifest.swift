import Foundation

public struct IntegrationManifest: Codable, Equatable, Sendable {
    public static let resourceName = "HarborIntegration.json"
    public let schema: Int
    public let appID: String
    public let bundleIdentifier: String
    public let minimumOS: String
    public let architecture: String
    public let permissions: [PermissionGuide]
    public init(app: AppDefinition) {
        schema = 1; appID = app.id; bundleIdentifier = app.bundleIdentifier
        minimumOS = app.minimumOS; architecture = "arm64"; permissions = app.permissions
    }
    public func matches(_ app: AppDefinition) -> Bool {
        schema == 1 && appID == app.id && bundleIdentifier == app.bundleIdentifier && architecture == "arm64"
    }
}
