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
