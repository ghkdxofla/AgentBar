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
    case business = "Business"
    case custom = "Custom"

    var monthlyRequestLimit: Double {
        switch self {
        case .free: return 50
        case .pro: return 500
        case .business: return 500
        case .custom: return 0
        }
    }
}
