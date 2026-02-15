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

    static func save(key: String, account: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.unexpectedData
        }

        // Build query with open ACL so any build of this app can read it
        var query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String:   data,
        ]

        // Create an open-access ACL: no app restriction, no password prompt
        var access: SecAccess?
        let accessStatus = SecAccessCreate("CCUsageBar API Key" as CFString, nil, &access)
        if accessStatus == errSecSuccess, let access = access {
            query[kSecAttrAccess as String] = access
        }

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}
