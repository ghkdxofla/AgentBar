import Foundation

enum ClaudePlan: String, CaseIterable, Codable, Sendable {
    case max5x = "Max 5x"
    case max20x = "Max 20x"
    case custom = "Custom"

    /// 5-hour burst budget in API-equivalent dollars
    var fiveHourBudget: Double {
        switch self {
        case .max5x:  103.0
        case .max20x: 412.0
        case .custom: 0
        }
    }

    /// Weekly sustained budget in API-equivalent dollars
    var weeklyBudget: Double {
        switch self {
        case .max5x:  1133.0
        case .max20x: 4532.0
        case .custom: 0
        }
    }
}

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
