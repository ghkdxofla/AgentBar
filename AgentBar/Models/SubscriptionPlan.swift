import Foundation

enum CodexPlan: String, CaseIterable, Codable, Sendable {
    case pro = "Pro"
    case custom = "Custom"

    var fiveHourTokenLimit: Double {
        switch self {
        case .pro: return 10_000_000
        case .custom: return 0
        }
    }

    var weeklyTokenLimit: Double {
        switch self {
        case .pro: return 100_000_000
        case .custom: return 0
        }
    }
}

enum CopilotPlan: String, CaseIterable, Codable, Sendable {
    case free = "Free"
    case pro = "Pro"
    case proPlus = "Pro+"
    case business = "Business"
    case enterprise = "Enterprise"
    case custom = "Custom"

    var monthlyPremiumRequests: Double {
        switch self {
        case .free: return 50
        case .pro: return 300
        case .proPlus: return 1500
        case .business: return 300
        case .enterprise: return 1000
        case .custom: return 0
        }
    }
}

enum CursorPlan: String, CaseIterable, Codable, Sendable {
    case free = "Free"
    case pro = "Pro"
    case proPlus = "Pro+"
    case ultra = "Ultra"
    case teams = "Teams"
    case custom = "Custom"

    /// Monthly credit in USD. Cursor switched to credit-based pricing in June 2025.
    var monthlyCreditDollars: Double {
        switch self {
        case .free: return 0
        case .pro: return 20
        case .proPlus: return 60
        case .ultra: return 200
        case .teams: return 40
        case .custom: return 0
        }
    }

    /// Approximate monthly premium request estimate (varies by model).
    /// Claude Sonnet ~225, GPT-5 ~500, Gemini ~550 per $20.
    var monthlyRequestEstimate: Double {
        switch self {
        case .free: return 50
        case .pro: return 500
        case .proPlus: return 1500
        case .ultra: return 5000
        case .teams: return 1000
        case .custom: return 0
        }
    }

    static func migrateLegacyRawValue(_ rawValue: String) -> String {
        switch rawValue {
        case "Business":
            return CursorPlan.teams.rawValue
        default:
            return rawValue
        }
    }

    static func resolveAndMigrateStoredPlan(in defaults: UserDefaults = .standard) -> CursorPlan {
        let storedRawValue = defaults.string(forKey: "cursorPlan") ?? CursorPlan.pro.rawValue
        let migratedRawValue = migrateLegacyRawValue(storedRawValue)

        if migratedRawValue != storedRawValue {
            defaults.set(migratedRawValue, forKey: "cursorPlan")
        }

        if let resolvedPlan = CursorPlan(rawValue: migratedRawValue) {
            return resolvedPlan
        }

        defaults.set(CursorPlan.pro.rawValue, forKey: "cursorPlan")
        return .pro
    }
}
