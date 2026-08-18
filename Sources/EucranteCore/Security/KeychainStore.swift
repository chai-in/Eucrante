import Foundation
import Security

public struct KeychainStore: Sendable {
  public let service: String

  public init(service: String = "app.eucrante.credentials") {
    self.service = service
  }

  public func set(_ value: String, for account: String) throws {
    guard let data = value.data(using: .utf8) else {
      throw KeychainError.invalidString
    }

    let lookup: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(lookup as CFDictionary)

    var attributes = lookup
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    let status = SecItemAdd(attributes as CFDictionary, nil)
    guard status == errSecSuccess else { throw KeychainError.status(status) }
  }

  public func string(for account: String) throws -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw KeychainError.status(status) }
    guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
      throw KeychainError.invalidString
    }
    return value
  }

  public func delete(account: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.status(status)
    }
  }
}

public enum KeychainError: LocalizedError, Equatable, Sendable {
  case invalidString
  case status(OSStatus)

  public var errorDescription: String? {
    switch self {
    case .invalidString:
      "The credential could not be encoded."
    case .status(let status):
      "Keychain returned error \(status)."
    }
  }
}
