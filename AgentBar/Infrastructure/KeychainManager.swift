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

    // Remember when dataProtection is unavailable (ad-hoc signing) to avoid redundant Keychain dialogs.
    private static let dpLock = NSLock()
    nonisolated(unsafe) private static var dataProtectionUnavailable = false

    // In-process cache for load results. Invalidated by save()/delete().
    // Prevents repeated SecItemCopyMatching calls that trigger macOS Keychain permission dialogs.
    private struct CachedValue {
        let value: String?
    }
    private static let loadCacheLock = NSLock()
    nonisolated(unsafe) private static var loadCache: [String: CachedValue] = [:]

    enum Store {
        case dataProtection
        case legacy
    }

    protocol SecurityAPI {
        func add(_ query: [String: Any]) -> OSStatus
        func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
        func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?)
        func delete(_ query: [String: Any]) -> OSStatus
    }

    struct SystemSecurityAPI: SecurityAPI {
        func add(_ query: [String: Any]) -> OSStatus {
            SecItemAdd(query as CFDictionary, nil)
        }

        func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
            SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        }

        func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            return (status, result as? Data)
        }

        func delete(_ query: [String: Any]) -> OSStatus {
            SecItemDelete(query as CFDictionary)
        }
    }

    static func save(key: String, account: String) throws {
        try save(key: key, account: account, securityAPI: SystemSecurityAPI())
        invalidateLoadCache(account: account)
    }

    static func save(key: String, account: String, securityAPI: any SecurityAPI) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.unexpectedData
        }

        // Write first, then clean legacy entry only after success.
        let dataProtectionStatus = upsert(
            data: data,
            account: account,
            store: .dataProtection,
            securityAPI: securityAPI
        )
        if dataProtectionStatus == errSecSuccess {
            _ = deleteStore(account: account, store: .legacy, securityAPI: securityAPI)
            return
        }

        // Some environments cannot write Data Protection keychain.
        if dataProtectionStatus == errSecMissingEntitlement {
            markDataProtectionUnavailable()
        } else {
            throw KeychainError.saveFailed(dataProtectionStatus)
        }

        let legacyStatus = upsert(
            data: data,
            account: account,
            store: .legacy,
            securityAPI: securityAPI
        )
        guard legacyStatus == errSecSuccess else {
            throw KeychainError.saveFailed(legacyStatus)
        }
    }

    static func load(account: String) -> String? {
        loadCacheLock.lock()
        if let cached = loadCache[account] {
            loadCacheLock.unlock()
            return cached.value
        }
        loadCacheLock.unlock()

        let value: String?
        if isDataProtectionUnavailable {
            value = loadLegacyOnly(account: account, securityAPI: SystemSecurityAPI())
        } else {
            value = load(account: account, securityAPI: SystemSecurityAPI())
        }

        loadCacheLock.lock()
        loadCache[account] = CachedValue(value: value)
        loadCacheLock.unlock()

        return value
    }

    static func load(account: String, securityAPI: any SecurityAPI) -> String? {
        let dataProtectionValue = copyValue(account: account, store: .dataProtection, securityAPI: securityAPI)
        if dataProtectionValue.status == errSecSuccess {
            guard let data = dataProtectionValue.data else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        }
        if dataProtectionValue.status == errSecMissingEntitlement {
            markDataProtectionUnavailable()
        }
        guard shouldFallbackToLegacyLoad(for: dataProtectionValue.status) else {
            return nil
        }

        let legacyValue = copyValue(account: account, store: .legacy, securityAPI: securityAPI)
        guard legacyValue.status == errSecSuccess,
              let legacyData = legacyValue.data,
              let value = String(data: legacyData, encoding: .utf8) else {
            return nil
        }

        let migrationStatus = upsert(
            data: legacyData,
            account: account,
            store: .dataProtection,
            securityAPI: securityAPI
        )
        if migrationStatus == errSecSuccess {
            _ = deleteStore(account: account, store: .legacy, securityAPI: securityAPI)
        }

        return value
    }

    static func delete(account: String) throws {
        try delete(account: account, securityAPI: SystemSecurityAPI())
        invalidateLoadCache(account: account)
    }

    static func delete(account: String, securityAPI: any SecurityAPI) throws {
        let dataProtectionStatus = deleteStore(account: account, store: .dataProtection, securityAPI: securityAPI)
        let legacyStatus = deleteStore(account: account, store: .legacy, securityAPI: securityAPI)

        guard isAllowedDeleteStatus(dataProtectionStatus, for: .dataProtection) else {
            throw KeychainError.deleteFailed(dataProtectionStatus)
        }
        guard isAllowedDeleteStatus(legacyStatus, for: .legacy) else {
            throw KeychainError.deleteFailed(legacyStatus)
        }
    }

    private static func upsert(
        data: Data,
        account: String,
        store: Store,
        securityAPI: any SecurityAPI
    ) -> OSStatus {
        let query = itemQuery(account: account, store: store)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        if store == .dataProtection {
            // Accessible is valid for Data Protection items and keeps secrets locked at rest.
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        }

        let addStatus = securityAPI.add(addQuery)
        if addStatus == errSecSuccess {
            return errSecSuccess
        }
        guard addStatus == errSecDuplicateItem else {
            return addStatus
        }

        return securityAPI.update(query, attributes: [kSecValueData as String: data])
    }

    private static func copyValue(
        account: String,
        store: Store,
        securityAPI: any SecurityAPI
    ) -> (status: OSStatus, data: Data?) {
        var query = itemQuery(account: account, store: store)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return securityAPI.copyMatching(query)
    }

    private static func deleteStore(
        account: String,
        store: Store,
        securityAPI: any SecurityAPI
    ) -> OSStatus {
        let query = itemQuery(account: account, store: store)
        return securityAPI.delete(query)
    }

    private static func itemQuery(account: String, store: Store) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if store == .dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    private static func isAllowedDeleteStatus(_ status: OSStatus, for store: Store) -> Bool {
        if status == errSecSuccess || status == errSecItemNotFound {
            return true
        }
        if store == .dataProtection && status == errSecMissingEntitlement {
            return true
        }
        return false
    }

    private static func shouldFallbackToLegacyLoad(for dataProtectionStatus: OSStatus) -> Bool {
        dataProtectionStatus == errSecItemNotFound || dataProtectionStatus == errSecMissingEntitlement
    }

    // MARK: - Data Protection Availability Cache

    private static var isDataProtectionUnavailable: Bool {
        dpLock.lock()
        defer { dpLock.unlock() }
        return dataProtectionUnavailable
    }

    private static func markDataProtectionUnavailable() {
        dpLock.lock()
        dataProtectionUnavailable = true
        dpLock.unlock()
    }

    private static func invalidateLoadCache(account: String) {
        loadCacheLock.lock()
        loadCache.removeValue(forKey: account)
        loadCacheLock.unlock()
    }

    /// Legacy-only fast path: skips dataProtection query entirely when entitlement is known to be missing.
    private static func loadLegacyOnly(account: String, securityAPI: any SecurityAPI) -> String? {
        let legacyValue = copyValue(account: account, store: .legacy, securityAPI: securityAPI)
        guard legacyValue.status == errSecSuccess,
              let data = legacyValue.data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
