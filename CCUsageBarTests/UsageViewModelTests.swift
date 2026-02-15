import XCTest
import Security
@testable import CCUsageBar

@MainActor
final class UsageViewModelTests: XCTestCase {

    func testFetchAllUsageWithMultipleProviders() async {
        let mockClaude = MockUsageProvider(
            serviceType: .claude,
            result: .success(UsageData.mock(service: .claude))
        )
        let mockCodex = MockUsageProvider(
            serviceType: .codex,
            result: .success(UsageData.mock(service: .codex))
        )

        let vm = UsageViewModel(providers: [mockClaude, mockCodex])
        await vm.fetchAllUsage()

        XCTAssertEqual(vm.usageData.count, 2)
        XCTAssertEqual(vm.usageData[0].service, .claude)
        XCTAssertEqual(vm.usageData[1].service, .codex)
    }

    func testProviderFailureReturnsZeroUsage() async {
        let failProvider = MockUsageProvider(
            serviceType: .codex,
            result: .failure(APIError.unauthorized)
        )
        let successProvider = MockUsageProvider(
            serviceType: .claude,
            result: .success(UsageData.mock(service: .claude))
        )

        let vm = UsageViewModel(providers: [failProvider, successProvider])
        await vm.fetchAllUsage()

        // Both show: successful provider + zero-usage fallback for failed provider
        XCTAssertEqual(vm.usageData.count, 2)
        let codexData = vm.usageData.first { $0.service == .codex }
        XCTAssertNotNil(codexData)
        XCTAssertEqual(codexData!.fiveHourUsage.used, 0)
    }

    func testAllFailuresStillShowBars() async {
        let failProvider = MockUsageProvider(
            serviceType: .claude,
            result: .failure(APIError.noData)
        )

        let vm = UsageViewModel(providers: [failProvider])
        await vm.fetchAllUsage()

        // Failed provider still returns a zero-usage entry
        XCTAssertEqual(vm.usageData.count, 1)
        XCTAssertEqual(vm.usageData.first?.fiveHourUsage.used, 0)
        XCTAssertNil(vm.lastError)
    }

    func testSuccessfulResultsClearsError() async {
        let provider = MockUsageProvider(
            serviceType: .claude,
            result: .success(UsageData.mock(service: .claude))
        )

        let vm = UsageViewModel(providers: [provider])
        vm.lastError = "previous error"
        await vm.fetchAllUsage()

        XCTAssertNil(vm.lastError)
    }

    func testServiceOrderIsMaintained() async {
        // Provide in reverse order
        let zai = MockUsageProvider(serviceType: .zai, result: .success(UsageData.mock(service: .zai)))
        let gemini = MockUsageProvider(serviceType: .gemini, result: .success(UsageData.mock(service: .gemini)))
        let claude = MockUsageProvider(serviceType: .claude, result: .success(UsageData.mock(service: .claude)))
        let codex = MockUsageProvider(serviceType: .codex, result: .success(UsageData.mock(service: .codex)))

        let vm = UsageViewModel(providers: [zai, gemini, claude, codex])
        await vm.fetchAllUsage()

        XCTAssertEqual(vm.usageData.count, 4)
        XCTAssertEqual(vm.usageData[0].service, .claude)
        XCTAssertEqual(vm.usageData[1].service, .codex)
        XCTAssertEqual(vm.usageData[2].service, .gemini)
        XCTAssertEqual(vm.usageData[3].service, .zai)
    }

    func testLegacyCursorPlanBusinessMigratesToTeams() {
        let suiteName = "CCUsageBarTests.CursorPlanMigration"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("Business", forKey: "cursorPlan")

        let resolvedPlan = CursorPlan.resolveAndMigrateStoredPlan(in: defaults)

        XCTAssertEqual(resolvedPlan, .teams)
        XCTAssertEqual(defaults.string(forKey: "cursorPlan"), CursorPlan.teams.rawValue)
    }

    func testUnknownCursorPlanRawValueFallsBackToProAndPersists() {
        let suiteName = "CCUsageBarTests.CursorPlanUnknownValueMigration"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("Legacy-Unknown-Plan", forKey: "cursorPlan")

        let resolvedPlan = CursorPlan.resolveAndMigrateStoredPlan(in: defaults)

        XCTAssertEqual(resolvedPlan, .pro)
        XCTAssertEqual(defaults.string(forKey: "cursorPlan"), CursorPlan.pro.rawValue)
    }

    func testSanitizedTokenForSavingRejectsMaskedPlaceholder() {
        XCTAssertNil(SettingsView.sanitizedTokenForSaving("*****"))
        XCTAssertNil(SettingsView.sanitizedTokenForSaving("   ******   "))
        XCTAssertEqual(SettingsView.sanitizedTokenForSaving("  ghp_valid_token  "), "ghp_valid_token")
    }

    func testSaveAPIKeyResultRejectsWhitespaceAndSkipsSave() {
        var didAttemptSave = false

        let result = SettingsView.saveAPIKeyResult("   ", account: "copilot-account") { _, _ in
            didAttemptSave = true
        }

        XCTAssertFalse(didAttemptSave)
        if case .failure(let message) = result {
            XCTAssertEqual(message, "Please enter a valid token before saving.")
        } else {
            XCTFail("Expected failure for whitespace token")
        }
    }

    func testSaveAPIKeyResultSavesTrimmedToken() {
        var savedKey: String?
        var savedAccount: String?

        let result = SettingsView.saveAPIKeyResult("  ghp_valid_token  ", account: "copilot-account") { key, account in
            savedKey = key
            savedAccount = account
        }

        if case .failure(let message) = result {
            XCTFail("Expected success, got failure: \(message)")
        }
        XCTAssertEqual(savedKey, "ghp_valid_token")
        XCTAssertEqual(savedAccount, "copilot-account")
    }

    func testSaveAPIKeyResultReturnsFailureWhenSaveThrows() {
        let result = SettingsView.saveAPIKeyResult("ghp_valid_token", account: "copilot-account") { _, _ in
            throw StubSaveError.keychainUnavailable
        }

        if case .failure(let message) = result {
            XCTAssertEqual(message, "Keychain unavailable")
        } else {
            XCTFail("Expected failure when keychain save throws")
        }
    }

    func testSaveAPIKeyResultReturnsFallbackFailureMessageWhenErrorDescriptionIsBlank() {
        let result = SettingsView.saveAPIKeyResult("ghp_valid_token", account: "copilot-account") { _, _ in
            throw NSError(
                domain: "CCUsageBarTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "   \n\t"]
            )
        }

        if case .failure(let message) = result {
            XCTAssertEqual(message, "Failed to save token to Keychain.")
        } else {
            XCTFail("Expected fallback failure message when error description is blank")
        }
    }

    func testTokenSaveUIOutcomeOnSuccessMarksSavedAndShowsSuccessAlert() {
        var savedKey: String?
        var savedAccount: String?

        let outcome = SettingsView.tokenSaveUIOutcome(
            currentToken: "  zai_live_key  ",
            hasSavedToken: false,
            account: ServiceType.zai.keychainAccount
        ) { key, account in
            savedKey = key
            savedAccount = account
        }

        XCTAssertTrue(outcome.didSave)
        XCTAssertTrue(outcome.hasSavedToken)
        XCTAssertEqual(outcome.tokenFieldValue, "")
        XCTAssertTrue(outcome.showSavedAlert)
        XCTAssertFalse(outcome.showSaveErrorAlert)
        XCTAssertEqual(outcome.saveErrorMessage, "")
        XCTAssertEqual(savedKey, "zai_live_key")
        XCTAssertEqual(savedAccount, ServiceType.zai.keychainAccount)
    }

    func testTokenSaveUIOutcomeOnFailurePreservesTokenAndShowsErrorAlert() {
        let outcome = SettingsView.tokenSaveUIOutcome(
            currentToken: "ghp_valid_token",
            hasSavedToken: false,
            account: ServiceType.copilot.keychainAccount
        ) { _, _ in
            throw StubSaveError.keychainUnavailable
        }

        XCTAssertFalse(outcome.didSave)
        XCTAssertFalse(outcome.hasSavedToken)
        XCTAssertEqual(outcome.tokenFieldValue, "ghp_valid_token")
        XCTAssertFalse(outcome.showSavedAlert)
        XCTAssertTrue(outcome.showSaveErrorAlert)
        XCTAssertEqual(outcome.saveErrorMessage, "Keychain unavailable")
    }

    func testCopilotPATSaveOutcomeMarksSavedAndClearsInputOnSuccess() {
        let outcome = SettingsView.copilotPATSaveOutcome(
            currentPAT: "ghp_valid_token",
            hasSavedCopilotPAT: false
        ) { _ in
            true
        }

        XCTAssertTrue(outcome.didSave)
        XCTAssertTrue(outcome.hasSavedCopilotPAT)
        XCTAssertEqual(outcome.copilotPAT, "")
    }

    func testCopilotPATSaveOutcomePreservesStateOnFailure() {
        let outcome = SettingsView.copilotPATSaveOutcome(
            currentPAT: "ghp_valid_token",
            hasSavedCopilotPAT: false
        ) { _ in
            false
        }

        XCTAssertFalse(outcome.didSave)
        XCTAssertFalse(outcome.hasSavedCopilotPAT)
        XCTAssertEqual(outcome.copilotPAT, "ghp_valid_token")
    }

    func testCopilotPATSaveOutcomeKeepsSavedStateOnFailureWhenAlreadySaved() {
        let outcome = SettingsView.copilotPATSaveOutcome(
            currentPAT: "ghp_valid_token",
            hasSavedCopilotPAT: true
        ) { _ in
            false
        }

        XCTAssertFalse(outcome.didSave)
        XCTAssertTrue(outcome.hasSavedCopilotPAT)
        XCTAssertEqual(outcome.copilotPAT, "ghp_valid_token")
    }

    func testKeychainSaveStoresInDataProtectionAndCleansLegacyOnSuccess() throws {
        let account = "tests.save.primary"
        let securityAPI = MockKeychainSecurityAPI(
            legacyItems: [account: Data("legacy-token".utf8)]
        )

        try KeychainManager.save(
            key: "new-token",
            account: account,
            securityAPI: securityAPI
        )

        XCTAssertEqual(securityAPI.dataProtectionItems[account], Data("new-token".utf8))
        XCTAssertNil(securityAPI.legacyItems[account])
    }

    func testKeychainSaveUpdatesExistingDataProtectionItemOnDuplicateAdd() throws {
        let account = "tests.save.upsert_update"
        let securityAPI = MockKeychainSecurityAPI(
            dataProtectionItems: [account: Data("original-token".utf8)]
        )

        try KeychainManager.save(
            key: "updated-token",
            account: account,
            securityAPI: securityAPI
        )

        XCTAssertEqual(securityAPI.dataProtectionItems[account], Data("updated-token".utf8))
    }

    func testKeychainSaveFallsBackToLegacyWhenDataProtectionMissingEntitlement() throws {
        let account = "tests.save.fallback"
        let securityAPI = MockKeychainSecurityAPI()
        securityAPI.addStatusByStore[.dataProtection] = errSecMissingEntitlement

        try KeychainManager.save(
            key: "fallback-token",
            account: account,
            securityAPI: securityAPI
        )

        XCTAssertNil(securityAPI.dataProtectionItems[account])
        XCTAssertEqual(securityAPI.legacyItems[account], Data("fallback-token".utf8))
    }

    func testKeychainSaveFailureDoesNotMutateLegacyWhenDataProtectionWriteFails() {
        let account = "tests.save.legacy_non_destructive"
        let legacyValue = Data("legacy-token".utf8)
        let securityAPI = MockKeychainSecurityAPI(legacyItems: [account: legacyValue])
        securityAPI.addStatusByStore[.dataProtection] = errSecInteractionNotAllowed

        XCTAssertThrowsError(
            try KeychainManager.save(
                key: "replacement-token",
                account: account,
                securityAPI: securityAPI
            )
        ) { error in
            guard case KeychainError.saveFailed(let status) = error else {
                return XCTFail("Expected KeychainError.saveFailed")
            }
            XCTAssertEqual(status, errSecInteractionNotAllowed)
        }
        XCTAssertEqual(securityAPI.legacyItems[account], legacyValue)
        XCTAssertNil(securityAPI.dataProtectionItems[account])
    }

    func testKeychainSavePreservesExistingDataProtectionItemWhenUpdateFails() {
        let account = "tests.save.non_destructive"
        let original = Data("original-token".utf8)
        let securityAPI = MockKeychainSecurityAPI(
            dataProtectionItems: [account: original]
        )
        securityAPI.updateStatusByStore[.dataProtection] = errSecInteractionNotAllowed

        XCTAssertThrowsError(
            try KeychainManager.save(
                key: "replacement-token",
                account: account,
                securityAPI: securityAPI
            )
        ) { error in
            guard case KeychainError.saveFailed(let status) = error else {
                return XCTFail("Expected KeychainError.saveFailed")
            }
            XCTAssertEqual(status, errSecInteractionNotAllowed)
        }
        XCTAssertEqual(securityAPI.dataProtectionItems[account], original)
    }

    func testKeychainLoadDoesNotFallbackToLegacyOnUnexpectedDataProtectionFailure() {
        let account = "tests.load.no_fallback_unexpected_status"
        let tokenData = Data("legacy-token".utf8)
        let securityAPI = MockKeychainSecurityAPI(legacyItems: [account: tokenData])
        securityAPI.copyStatusByStore[.dataProtection] = errSecInteractionNotAllowed

        let loaded = KeychainManager.load(account: account, securityAPI: securityAPI)

        XCTAssertNil(loaded)
        XCTAssertEqual(securityAPI.legacyItems[account], tokenData)
        XCTAssertNil(securityAPI.dataProtectionItems[account])
    }

    func testKeychainLoadFallsBackToLegacyOnMissingEntitlementAndKeepsLegacyWhenMigrationFails() {
        let account = "tests.load.fallback_missing_entitlement"
        let tokenData = Data("legacy-token".utf8)
        let securityAPI = MockKeychainSecurityAPI(legacyItems: [account: tokenData])
        securityAPI.copyStatusByStore[.dataProtection] = errSecMissingEntitlement
        securityAPI.addStatusByStore[.dataProtection] = errSecMissingEntitlement

        let loaded = KeychainManager.load(account: account, securityAPI: securityAPI)

        XCTAssertEqual(loaded, "legacy-token")
        XCTAssertNil(securityAPI.dataProtectionItems[account])
        XCTAssertEqual(securityAPI.legacyItems[account], tokenData)
    }

    func testKeychainLoadMigratesLegacyItemWhenDataProtectionSaveSucceeds() {
        let account = "tests.migration.success"
        let tokenData = Data("legacy-token".utf8)
        let securityAPI = MockKeychainSecurityAPI(legacyItems: [account: tokenData])

        let loaded = KeychainManager.load(account: account, securityAPI: securityAPI)

        XCTAssertEqual(loaded, "legacy-token")
        XCTAssertEqual(securityAPI.dataProtectionItems[account], tokenData)
        XCTAssertNil(securityAPI.legacyItems[account])
    }

    func testKeychainLoadKeepsLegacyItemWhenMigrationSaveFails() {
        let account = "tests.migration.failure"
        let tokenData = Data("legacy-token".utf8)
        let securityAPI = MockKeychainSecurityAPI(legacyItems: [account: tokenData])
        securityAPI.addStatusByStore[.dataProtection] = errSecInteractionNotAllowed

        let loaded = KeychainManager.load(account: account, securityAPI: securityAPI)

        XCTAssertEqual(loaded, "legacy-token")
        XCTAssertNil(securityAPI.dataProtectionItems[account])
        XCTAssertEqual(securityAPI.legacyItems[account], tokenData)
    }

    func testKeychainDeleteRemovesDataProtectionAndLegacyItems() throws {
        let account = "tests.delete.cleanup"
        let tokenData = Data("token".utf8)
        let securityAPI = MockKeychainSecurityAPI(
            dataProtectionItems: [account: tokenData],
            legacyItems: [account: tokenData]
        )

        try KeychainManager.delete(account: account, securityAPI: securityAPI)

        XCTAssertNil(securityAPI.dataProtectionItems[account])
        XCTAssertNil(securityAPI.legacyItems[account])
    }

    func testKeychainDeleteThrowsForUnexpectedLegacyDeleteFailure() {
        let account = "tests.delete.failure"
        let securityAPI = MockKeychainSecurityAPI(legacyItems: [account: Data("token".utf8)])
        securityAPI.deleteStatusByStore[.legacy] = errSecInteractionNotAllowed

        XCTAssertThrowsError(try KeychainManager.delete(account: account, securityAPI: securityAPI)) { error in
            guard case KeychainError.deleteFailed(let status) = error else {
                return XCTFail("Expected KeychainError.deleteFailed")
            }
            XCTAssertEqual(status, errSecInteractionNotAllowed)
        }
    }

    func testKeychainFallbackSaveWorksWithSystemSecurityAPI() throws {
        let account = "tests.integration.legacy.\(UUID().uuidString)"
        let token = "integration-token"
        let securityAPI = DataProtectionUnavailableSystemSecurityAPI()

        defer {
            try? KeychainManager.delete(account: account, securityAPI: securityAPI)
        }

        do {
            try KeychainManager.save(key: token, account: account, securityAPI: securityAPI)
        } catch KeychainError.saveFailed(let status)
            where Self.isSkippableSystemKeychainStatus(
                status,
                didAttemptLegacyFallback: securityAPI.legacyWriteAttemptCount > 0
            ) {
            throw XCTSkip("System keychain unavailable in this test environment (status: \(status))")
        }

        XCTAssertEqual(
            securityAPI.dataProtectionAddRejectionCount,
            1,
            "Expected the Data Protection write path to be attempted and rejected once before fallback"
        )
        XCTAssertEqual(
            securityAPI.legacyAddAttemptCount,
            1,
            "Expected exactly one legacy add attempt for a new account"
        )
        XCTAssertEqual(
            securityAPI.legacyUpdateAttemptCount,
            0,
            "Expected no legacy update attempt for a new account"
        )

        let loaded = KeychainManager.load(account: account, securityAPI: securityAPI)
        if loaded == nil {
            let fallbackCopyStatus = securityAPI.copyMatching([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.agentbar.apikeys",
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]).status
            if Self.isSkippableSystemKeychainStatus(
                fallbackCopyStatus,
                didAttemptLegacyFallback: securityAPI.legacyWriteAttemptCount > 0
            ) {
                throw XCTSkip("System keychain unavailable in this test environment (status: \(fallbackCopyStatus))")
            }
        }

        XCTAssertEqual(loaded, token)
    }

    func testMockKeychainSecurityAPIRejectsMalformedCopyQuery() {
        let securityAPI = MockKeychainSecurityAPI()

        let result = securityAPI.copyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.agentbar.apikeys",
            kSecAttrAccount as String: "tests.invalid.copy"
        ])

        XCTAssertEqual(result.status, errSecParam)
        XCTAssertNil(result.data)
    }

    func testMockKeychainSecurityAPIRejectsMalformedAddQuery() {
        let account = "tests.invalid.add"
        let securityAPI = MockKeychainSecurityAPI()

        let status = securityAPI.add([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.agentbar.apikeys",
            kSecAttrAccount as String: account,
            kSecValueData as String: Data("token".utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ])

        XCTAssertEqual(status, errSecParam)
        XCTAssertNil(securityAPI.dataProtectionItems[account])
        XCTAssertNil(securityAPI.legacyItems[account])
    }

    func testMockKeychainSecurityAPIRejectsMalformedUpdateQuery() {
        let account = "tests.invalid.update"
        let existingData = Data("existing-token".utf8)
        let securityAPI = MockKeychainSecurityAPI(legacyItems: [account: existingData])

        let status = securityAPI.update([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.agentbar.apikeys",
            kSecAttrAccount as String: account
        ], attributes: [
            kSecValueData as String: Data("replacement-token".utf8),
            kSecReturnData as String: true
        ])

        XCTAssertEqual(status, errSecParam)
        XCTAssertEqual(securityAPI.legacyItems[account], existingData)
    }

    func testMockKeychainSecurityAPIRejectsMalformedDeleteQuery() {
        let account = "tests.invalid.delete"
        let existingData = Data("existing-token".utf8)
        let securityAPI = MockKeychainSecurityAPI(legacyItems: [account: existingData])

        let status = securityAPI.delete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.agentbar.apikeys",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ])

        XCTAssertEqual(status, errSecParam)
        XCTAssertEqual(securityAPI.legacyItems[account], existingData)
    }

    private static func isSkippableSystemKeychainStatus(
        _ status: OSStatus,
        didAttemptLegacyFallback: Bool = false
    ) -> Bool {
        switch status {
        case errSecNotAvailable,
             errSecInteractionNotAllowed,
             errSecAuthFailed,
             errSecNoSuchKeychain:
            true
        case errSecMissingEntitlement:
            didAttemptLegacyFallback
        default:
            false
        }
    }

}

private enum StubSaveError: LocalizedError {
    case keychainUnavailable

    var errorDescription: String? {
        switch self {
        case .keychainUnavailable:
            return "Keychain unavailable"
        }
    }
}

private final class MockKeychainSecurityAPI: KeychainManager.SecurityAPI {
    private let expectedService = "com.agentbar.apikeys"

    enum Store {
        case dataProtection
        case legacy
    }

    var dataProtectionItems: [String: Data]
    var legacyItems: [String: Data]
    var addStatusByStore: [Store: OSStatus] = [:]
    var updateStatusByStore: [Store: OSStatus] = [:]
    var copyStatusByStore: [Store: OSStatus] = [:]
    var deleteStatusByStore: [Store: OSStatus] = [:]

    init(
        dataProtectionItems: [String: Data] = [:],
        legacyItems: [String: Data] = [:]
    ) {
        self.dataProtectionItems = dataProtectionItems
        self.legacyItems = legacyItems
    }

    func add(_ query: [String : Any]) -> OSStatus {
        guard let (store, account) = parse(query) else {
            return errSecParam
        }
        if let compatibilityError = validateAddQueryCompatibility(query, store: store) {
            return compatibilityError
        }
        if let forced = addStatusByStore[store], forced != errSecSuccess {
            return forced
        }
        guard let data = query[kSecValueData as String] as? Data else {
            return errSecParam
        }

        switch store {
        case .dataProtection:
            if dataProtectionItems[account] != nil {
                return errSecDuplicateItem
            }
            dataProtectionItems[account] = data
        case .legacy:
            if legacyItems[account] != nil {
                return errSecDuplicateItem
            }
            legacyItems[account] = data
        }
        return errSecSuccess
    }

    func update(_ query: [String : Any], attributes: [String : Any]) -> OSStatus {
        guard let (store, account) = parse(query) else {
            return errSecParam
        }
        if let compatibilityError = validateUpdateQueryCompatibility(query, attributes: attributes) {
            return compatibilityError
        }
        if let forced = updateStatusByStore[store], forced != errSecSuccess {
            return forced
        }
        guard let data = attributes[kSecValueData as String] as? Data else {
            return errSecParam
        }

        switch store {
        case .dataProtection:
            guard dataProtectionItems[account] != nil else {
                return errSecItemNotFound
            }
            dataProtectionItems[account] = data
        case .legacy:
            guard legacyItems[account] != nil else {
                return errSecItemNotFound
            }
            legacyItems[account] = data
        }
        return errSecSuccess
    }

    func copyMatching(_ query: [String : Any]) -> (status: OSStatus, data: Data?) {
        guard let (store, account) = parse(query) else {
            return (errSecParam, nil)
        }
        if let compatibilityError = validateCopyQueryCompatibility(query) {
            return (compatibilityError, nil)
        }
        if let forced = copyStatusByStore[store], forced != errSecSuccess {
            return (forced, nil)
        }

        switch store {
        case .dataProtection:
            guard let data = dataProtectionItems[account] else {
                return (errSecItemNotFound, nil)
            }
            return (errSecSuccess, data)
        case .legacy:
            guard let data = legacyItems[account] else {
                return (errSecItemNotFound, nil)
            }
            return (errSecSuccess, data)
        }
    }

    func delete(_ query: [String : Any]) -> OSStatus {
        guard let (store, account) = parse(query) else {
            return errSecParam
        }
        if let compatibilityError = validateDeleteQueryCompatibility(query) {
            return compatibilityError
        }
        if let forced = deleteStatusByStore[store], forced != errSecSuccess {
            return forced
        }

        switch store {
        case .dataProtection:
            guard dataProtectionItems.removeValue(forKey: account) != nil else {
                return errSecItemNotFound
            }
        case .legacy:
            guard legacyItems.removeValue(forKey: account) != nil else {
                return errSecItemNotFound
            }
        }
        return errSecSuccess
    }

    private func parse(_ query: [String: Any]) -> (Store, String)? {
        guard isSecConstant(
            query[kSecClass as String],
            expected: kSecClassGenericPassword
        ) else {
            return nil
        }
        guard let service = query[kSecAttrService as String] as? String,
              service == expectedService else {
            return nil
        }
        guard let account = query[kSecAttrAccount as String] as? String,
              !account.isEmpty else {
            return nil
        }
        if let dataProtectionFlag = query[kSecUseDataProtectionKeychain as String] {
            guard let enabled = dataProtectionFlag as? Bool, enabled else {
                return nil
            }
            return (.dataProtection, account)
        }
        return (.legacy, account)
    }

    private func validateAddQueryCompatibility(_ query: [String: Any], store: Store) -> OSStatus? {
        let allowedKeys: Set<String> = [
            kSecClass as String,
            kSecAttrService as String,
            kSecAttrAccount as String,
            kSecUseDataProtectionKeychain as String,
            kSecValueData as String,
            kSecAttrAccessible as String
        ]
        guard hasOnlyAllowedKeys(query, allowed: allowedKeys) else {
            return errSecParam
        }
        guard query[kSecValueData as String] is Data else {
            return errSecParam
        }

        if store == .legacy {
            if query[kSecAttrAccessible as String] != nil {
                return errSecParam
            }
            return nil
        }

        guard isSecConstant(
            query[kSecAttrAccessible as String],
            expected: kSecAttrAccessibleWhenUnlocked
        ) else {
            return errSecParam
        }
        return nil
    }

    private func validateUpdateQueryCompatibility(
        _ query: [String: Any],
        attributes: [String: Any]
    ) -> OSStatus? {
        let allowedQueryKeys: Set<String> = [
            kSecClass as String,
            kSecAttrService as String,
            kSecAttrAccount as String,
            kSecUseDataProtectionKeychain as String
        ]
        guard hasOnlyAllowedKeys(query, allowed: allowedQueryKeys) else {
            return errSecParam
        }

        let expectedAttributeKeys: Set<String> = [kSecValueData as String]
        guard Set(attributes.keys) == expectedAttributeKeys,
              attributes[kSecValueData as String] is Data else {
            return errSecParam
        }

        return nil
    }

    private func validateCopyQueryCompatibility(_ query: [String: Any]) -> OSStatus? {
        let allowedKeys: Set<String> = [
            kSecClass as String,
            kSecAttrService as String,
            kSecAttrAccount as String,
            kSecUseDataProtectionKeychain as String,
            kSecReturnData as String,
            kSecMatchLimit as String
        ]
        guard hasOnlyAllowedKeys(query, allowed: allowedKeys) else {
            return errSecParam
        }
        guard (query[kSecReturnData as String] as? Bool) == true else {
            return errSecParam
        }
        guard isSecConstant(
            query[kSecMatchLimit as String],
            expected: kSecMatchLimitOne
        ) else {
            return errSecParam
        }
        return nil
    }

    private func validateDeleteQueryCompatibility(_ query: [String: Any]) -> OSStatus? {
        let allowedKeys: Set<String> = [
            kSecClass as String,
            kSecAttrService as String,
            kSecAttrAccount as String,
            kSecUseDataProtectionKeychain as String
        ]
        guard hasOnlyAllowedKeys(query, allowed: allowedKeys) else {
            return errSecParam
        }
        return nil
    }

    private func hasOnlyAllowedKeys(_ query: [String: Any], allowed: Set<String>) -> Bool {
        Set(query.keys).isSubset(of: allowed)
    }

    private func isSecConstant(_ value: Any?, expected: CFString) -> Bool {
        guard let value else {
            return false
        }
        return String(describing: value) == expected as String
    }
}

private final class DataProtectionUnavailableSystemSecurityAPI: KeychainManager.SecurityAPI {
    private let systemAPI = KeychainManager.SystemSecurityAPI()
    private(set) var dataProtectionAddRejectionCount = 0
    private(set) var legacyAddAttemptCount = 0
    private(set) var legacyUpdateAttemptCount = 0

    var legacyWriteAttemptCount: Int {
        legacyAddAttemptCount + legacyUpdateAttemptCount
    }

    func add(_ query: [String : Any]) -> OSStatus {
        if (query[kSecUseDataProtectionKeychain as String] as? Bool) == true {
            dataProtectionAddRejectionCount += 1
            return errSecMissingEntitlement
        }
        legacyAddAttemptCount += 1
        return systemAPI.add(query)
    }

    func update(_ query: [String : Any], attributes: [String : Any]) -> OSStatus {
        if (query[kSecUseDataProtectionKeychain as String] as? Bool) != true {
            legacyUpdateAttemptCount += 1
        }
        return systemAPI.update(query, attributes: attributes)
    }

    func copyMatching(_ query: [String : Any]) -> (status: OSStatus, data: Data?) {
        systemAPI.copyMatching(query)
    }

    func delete(_ query: [String : Any]) -> OSStatus {
        systemAPI.delete(query)
    }
}
