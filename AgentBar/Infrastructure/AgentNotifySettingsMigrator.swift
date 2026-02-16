import Foundation
import os.log

enum AgentNotifySettingsMigrator {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.agentbar.app",
        category: "AgentNotifySettingsMigrator"
    )

    private static let keyMappings: [String: String] = [
        "alertsEnabled": "notificationsEnabled",
        "alertTaskCompletedEnabled": "notificationTaskCompletedEnabled",
        "alertCodexEventsEnabled": "notificationCodexEventsEnabled",
        "alertClaudeHookEventsEnabled": "notificationClaudeHookEventsEnabled",
        "alertShowMessagePreview": "notificationShowMessagePreview",
        "alertSoundPackPath": "notificationSoundPackPath",
        "alertSoundVolume": "notificationSoundVolume",
        "alertSoundTaskCompleteEnabled": "notificationSoundTaskCompleteEnabled",
        "alertSoundInputRequiredEnabled": "notificationSoundInputRequiredEnabled",
        // Legacy Phase-1 single watermark key from older roadmap iterations.
        "alertLastSeenCodexTimestamp": "notificationLastSeen_openai_codex"
    ]

    private static let legacyInputToggleKeys: [String] = [
        "notificationPermissionRequiredEnabled",
        "notificationDecisionRequiredEnabled",
        "alertPermissionRequiredEnabled",
        "alertDecisionRequiredEnabled"
    ]

    static func migrateIfNeeded(defaults: UserDefaults = .standard) {
        var migratedCount = 0
        var removedCount = 0

        if migrateInputRequiredToggle(defaults: defaults) {
            migratedCount += 1
        }
        removedCount += removeLegacyInputToggleKeys(defaults: defaults)

        for (oldKey, newKey) in keyMappings {
            if migrateValue(from: oldKey, to: newKey, defaults: defaults) {
                migratedCount += 1
            }
            if removeValueIfPresent(for: oldKey, defaults: defaults) {
                removedCount += 1
            }
        }

        let allKeys = Array(defaults.dictionaryRepresentation().keys)
        for key in allKeys where key.hasPrefix("alertLastSeen_") {
            let newKey = "notificationLastSeen_\(key.dropFirst("alertLastSeen_".count))"
            if migrateValue(from: key, to: newKey, defaults: defaults) {
                migratedCount += 1
            }
            if removeValueIfPresent(for: key, defaults: defaults) {
                removedCount += 1
            }
        }

        if removeValueIfPresent(for: "alertPollingSeconds", defaults: defaults) {
            removedCount += 1
        }

        guard migratedCount > 0 || removedCount > 0 else { return }
        logger.info(
            "Migrated legacy alert keys. migrated=\(migratedCount, privacy: .public), removed=\(removedCount, privacy: .public)"
        )
    }

    private static func migrateInputRequiredToggle(defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: "notificationInputRequiredEnabled") == nil else { return false }

        var legacyValues: [Bool] = []
        for key in legacyInputToggleKeys where defaults.object(forKey: key) != nil {
            legacyValues.append(defaults.bool(forKey: key))
        }

        guard !legacyValues.isEmpty else { return false }
        defaults.set(legacyValues.contains(true), forKey: "notificationInputRequiredEnabled")
        return true
    }

    private static func removeLegacyInputToggleKeys(defaults: UserDefaults) -> Int {
        legacyInputToggleKeys.reduce(into: 0) { count, key in
            if removeValueIfPresent(for: key, defaults: defaults) {
                count += 1
            }
        }
    }

    private static func migrateValue(from oldKey: String, to newKey: String, defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: newKey) == nil,
              let value = defaults.object(forKey: oldKey) else {
            return false
        }
        defaults.set(value, forKey: newKey)
        return true
    }

    private static func removeValueIfPresent(for key: String, defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: key) != nil else { return false }
        defaults.removeObject(forKey: key)
        return true
    }
}
