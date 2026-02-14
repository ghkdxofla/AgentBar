import Foundation

enum ClaudePlan: String, CaseIterable, Codable, Sendable {
    case max5x = "Max 5x"
    case max20x = "Max 20x"
    case custom = "Custom"

    var fiveHourTokenLimit: Double {
        switch self {
        case .max5x: return 2_500_000
        case .max20x: return 10_000_000
        case .custom: return 0
        }
    }

    var weeklyTokenLimit: Double {
        switch self {
        case .max5x: return 50_000_000
        case .max20x: return 200_000_000
        case .custom: return 0
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
