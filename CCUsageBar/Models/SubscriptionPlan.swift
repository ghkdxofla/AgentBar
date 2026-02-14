import Foundation

enum ClaudePlan: String, CaseIterable, Codable, Sendable {
    case max5x = "Max 5x"
    case max20x = "Max 20x"
    case custom = "Custom"

    var fiveHourTokenLimit: Double {
        switch self {
        case .max5x:  45_000_000
        case .max20x: 180_000_000
        case .custom: 0
        }
    }

    var weeklyTokenLimit: Double {
        switch self {
        case .max5x:  500_000_000
        case .max20x: 2_000_000_000
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
