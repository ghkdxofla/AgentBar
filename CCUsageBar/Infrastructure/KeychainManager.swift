import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case unexpectedData

    var errorDescription: String? {
        switch self {
        case .saveFailed(let s): "Keychain save failed (status: \(s))"
        case .loadFailed(let s): "Keychain load failed (status: \(s))"
        case .deleteFailed(let s): "Keychain delete failed (status: \(s))"
        case .unexpectedData: "Unexpected keychain data format"
        }
    }
}

enum KeychainManager {
    private static let service = "com.agentbar.apikeys"

    /// Base query using Data Protection Keychain (no per-app ACL prompts).
    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String:                    kSecClassGenericPassword,
            kSecAttrService as String:              service,
            kSecAttrAccount as String:              account,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrAccessible as String:           kSecAttrAccessibleWhenUnlocked,
        ]
    }

    static func save(key: String, account: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.unexpectedData
        }

        // Migrate: delete from legacy keychain if present
        deleteLegacyItem(account: account)

        var query = baseQuery(account: account)
        query[kSecValueData as String] = data

        // Delete existing item first
        let deleteQuery = baseQuery(account: account)
        SecItemDelete(deleteQuery as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func load(account: String) -> String? {
        // Try Data Protection Keychain first
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }

        // Fall back to legacy keychain for items saved before migration
        let legacyQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        result = nil
        status = SecItemCopyMatching(legacyQuery as CFDictionary, &result)
        guard status == errSecSuccess, let legacyData = result as? Data,
              let value = String(data: legacyData, encoding: .utf8) else {
            return nil
        }

        // Auto-migrate to Data Protection Keychain
        try? save(key: value, account: account)
        return value
    }

    static func delete(account: String) throws {
        let query = baseQuery(account: account)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
        // Also clean up legacy item if it exists
        deleteLegacyItem(account: account)
    }

    private static func deleteLegacyItem(account: String) {
        let legacyQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(legacyQuery as CFDictionary)
    }
}
