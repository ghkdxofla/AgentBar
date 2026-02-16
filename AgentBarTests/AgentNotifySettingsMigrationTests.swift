import XCTest
@testable import AgentBar

final class AgentHookConfigurationCheckerTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testDetectsConfiguredCodexAndClaudeHooks() throws {
        let codexConfig = tempDir.appendingPathComponent("codex.toml")
        try """
        notify = ["/tmp/agentbar-codex-hook.sh"]
        """.write(to: codexConfig, atomically: true, encoding: .utf8)

        let claudeSettings = tempDir.appendingPathComponent("claude.json")
        try """
        {"hooks":{"Stop":[{"hooks":[{"type":"command","command":"scripts/agentbar-hook.sh"}]}]}}
        """.write(to: claudeSettings, atomically: true, encoding: .utf8)

        let checker = AgentHookConfigurationChecker(
            codexConfigURL: codexConfig,
            claudeConfigURLs: [claudeSettings]
        )
        let now = Date(timeIntervalSince1970: 1_739_616_000)
        let status = checker.check(now: now)

        XCTAssertTrue(status.codex.isConfigured)
        XCTAssertTrue(status.claude.isConfigured)
        XCTAssertEqual(status.checkedAt, now)
    }

    func testReportsUnconfiguredHooksWhenAgentBarCommandIsMissing() throws {
        let codexConfig = tempDir.appendingPathComponent("codex.toml")
        try """
        model = "gpt-5.3-codex"
        """.write(to: codexConfig, atomically: true, encoding: .utf8)

        let claudeSettings = tempDir.appendingPathComponent("claude.json")
        try """
        {"hooks":{"Stop":[{"hooks":[{"type":"command","command":"osascript -e 'display notification \\"done\\"'"}]}]}}
        """.write(to: claudeSettings, atomically: true, encoding: .utf8)

        let checker = AgentHookConfigurationChecker(
            codexConfigURL: codexConfig,
            claudeConfigURLs: [claudeSettings]
        )
        let status = checker.check()

        XCTAssertFalse(status.codex.isConfigured)
        XCTAssertFalse(status.claude.isConfigured)
    }

    func testTreatsNotifyInsideTableAsUnconfigured() throws {
        let codexConfig = tempDir.appendingPathComponent("codex.toml")
        try """
        [mcp_servers.chrome-devtools]
        command = "npx"
        notify = ["/tmp/agentbar-codex-hook.sh"]
        """.write(to: codexConfig, atomically: true, encoding: .utf8)

        let checker = AgentHookConfigurationChecker(
            codexConfigURL: codexConfig,
            claudeConfigURLs: []
        )
        let status = checker.check()

        XCTAssertFalse(status.codex.isConfigured)
        XCTAssertTrue(status.codex.detail.contains("not configured"))
    }
}

final class AgentNotifySettingsMigratorTests: XCTestCase {
    func testMergesLegacyInputToggleKeysIntoUnifiedSetting() {
        let suiteName = "AgentBarTests.AgentNotifySettingsMigrator.InputMerge.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: "notificationPermissionRequiredEnabled")
        defaults.set(true, forKey: "notificationDecisionRequiredEnabled")

        AgentNotifySettingsMigrator.migrateIfNeeded(defaults: defaults)

        XCTAssertEqual(defaults.object(forKey: "notificationInputRequiredEnabled") as? Bool, true)
        XCTAssertNil(defaults.object(forKey: "notificationPermissionRequiredEnabled"))
        XCTAssertNil(defaults.object(forKey: "notificationDecisionRequiredEnabled"))
    }

    func testMergesAlertLegacyInputToggleKeysIntoUnifiedSetting() {
        let suiteName = "AgentBarTests.AgentNotifySettingsMigrator.AlertInputMerge.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: "alertPermissionRequiredEnabled")
        defaults.set(true, forKey: "alertDecisionRequiredEnabled")

        AgentNotifySettingsMigrator.migrateIfNeeded(defaults: defaults)

        XCTAssertEqual(defaults.object(forKey: "notificationInputRequiredEnabled") as? Bool, true)
        XCTAssertNil(defaults.object(forKey: "alertPermissionRequiredEnabled"))
        XCTAssertNil(defaults.object(forKey: "alertDecisionRequiredEnabled"))
    }

    func testDoesNotOverwriteUnifiedInputSetting() {
        let suiteName = "AgentBarTests.AgentNotifySettingsMigrator.InputNoOverwrite.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: "notificationInputRequiredEnabled")
        defaults.set(true, forKey: "notificationPermissionRequiredEnabled")
        defaults.set(true, forKey: "notificationDecisionRequiredEnabled")

        AgentNotifySettingsMigrator.migrateIfNeeded(defaults: defaults)

        XCTAssertEqual(defaults.object(forKey: "notificationInputRequiredEnabled") as? Bool, false)
        XCTAssertNil(defaults.object(forKey: "notificationPermissionRequiredEnabled"))
        XCTAssertNil(defaults.object(forKey: "notificationDecisionRequiredEnabled"))
    }

    func testMigratesLegacyKeysAndRemovesOldKeys() {
        let suiteName = "AgentBarTests.AgentNotifySettingsMigrator.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "alertsEnabled")
        defaults.set(true, forKey: "alertShowMessagePreview")
        defaults.set(0.5, forKey: "alertSoundVolume")
        defaults.set(1_739_616_000.5, forKey: "alertLastSeen_openai_codex")
        defaults.set(["abc"], forKey: "alertLastSeen_openai_codex_eventIDs")
        defaults.set(2, forKey: "alertLastSeen_openai_codex_cursorSchemaVersion")
        defaults.set(5.0, forKey: "alertPollingSeconds")

        AgentNotifySettingsMigrator.migrateIfNeeded(defaults: defaults)

        XCTAssertEqual(defaults.object(forKey: "notificationsEnabled") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "notificationShowMessagePreview") as? Bool, true)
        XCTAssertEqual(defaults.double(forKey: "notificationSoundVolume"), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(defaults.double(forKey: "notificationLastSeen_openai_codex"), 1_739_616_000.5, accuracy: 0.000_001)
        XCTAssertEqual(defaults.stringArray(forKey: "notificationLastSeen_openai_codex_eventIDs"), ["abc"])
        XCTAssertEqual(defaults.integer(forKey: "notificationLastSeen_openai_codex_cursorSchemaVersion"), 2)

        XCTAssertNil(defaults.object(forKey: "alertsEnabled"))
        XCTAssertNil(defaults.object(forKey: "alertShowMessagePreview"))
        XCTAssertNil(defaults.object(forKey: "alertSoundVolume"))
        XCTAssertNil(defaults.object(forKey: "alertLastSeen_openai_codex"))
        XCTAssertNil(defaults.object(forKey: "alertLastSeen_openai_codex_eventIDs"))
        XCTAssertNil(defaults.object(forKey: "alertLastSeen_openai_codex_cursorSchemaVersion"))
        XCTAssertNil(defaults.object(forKey: "alertPollingSeconds"))
    }

    func testDoesNotOverwriteExistingNotificationValues() {
        let suiteName = "AgentBarTests.AgentNotifySettingsMigrator.NoOverwrite.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: "notificationsEnabled")
        defaults.set(true, forKey: "alertsEnabled")

        AgentNotifySettingsMigrator.migrateIfNeeded(defaults: defaults)

        XCTAssertEqual(defaults.object(forKey: "notificationsEnabled") as? Bool, false)
        XCTAssertNil(defaults.object(forKey: "alertsEnabled"))
    }
}
