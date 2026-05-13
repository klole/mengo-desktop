import Foundation
import Security

/// Abstracts secret storage so `AccountStore` tests don't touch the real Keychain.
protocol SecretStore: Sendable {
    func set(_ value: String, for key: String)
    func get(_ key: String) -> String?
    func delete(_ key: String)
}

/// macOS Keychain (`kSecClassGenericPassword`, service `ai.mengo.desktop`).
/// Used in production to hold the Mengo session token (key `mengo.sessionToken`).
struct KeychainStore: SecretStore {
    private let service = "ai.mengo.desktop"

    func set(_ value: String, for key: String) {
        delete(key)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(attrs as CFDictionary, nil)
    }

    func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// In-memory `SecretStore` for tests.
final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    func set(_ value: String, for key: String) { storage[key] = value }
    func get(_ key: String) -> String? { storage[key] }
    func delete(_ key: String) { storage[key] = nil }
}

enum SecretKeys { static let sessionToken = "mengo.sessionToken" }
