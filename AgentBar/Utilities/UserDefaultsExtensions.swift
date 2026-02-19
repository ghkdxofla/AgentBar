import Foundation

enum NotificationSoundMode: String, CaseIterable, Sendable {
    case system
    case mute

    static let defaultsKey = "notificationSoundMode"

    static func resolve(from defaults: UserDefaults) -> NotificationSoundMode {
        guard let rawValue = defaults.string(forKey: defaultsKey),
              let mode = NotificationSoundMode(rawValue: rawValue) else {
            return .system
        }
        return mode
    }
}

enum BuyMeACoffeeSettings {
    static let hideButtonKey = "hideBuyMeACoffeeButton"
}

enum CopilotCredentialSettings {
    /// Enables Keychain fallback for Copilot when gh CLI token is unavailable.
    static let manualPATEnabledKey = "copilotManualPATEnabled"
}

extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        guard object(forKey: key) != nil else { return defaultValue }
        return bool(forKey: key)
    }
}

extension String {
    func capitalizingFirstCharacter() -> String {
        guard !isEmpty else { return self }
        return prefix(1).uppercased() + dropFirst()
    }
}
