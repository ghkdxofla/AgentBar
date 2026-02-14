import SwiftUI

enum ServiceType: String, CaseIterable, Codable, Sendable {
    case claude = "Claude Code"
    case codex  = "OpenAI Codex"
    case zai    = "Z.ai Coding Plan"

    var darkColor: Color {
        switch self {
        case .claude: Color(red: 0.851, green: 0.467, blue: 0.024) // amber-600
        case .codex:  Color(red: 0.020, green: 0.588, blue: 0.412) // emerald-600
        case .zai:    Color(red: 0.486, green: 0.227, blue: 0.929) // violet-600
        }
    }

    var lightColor: Color {
        switch self {
        case .claude: Color(red: 0.988, green: 0.827, blue: 0.302) // amber-300
        case .codex:  Color(red: 0.431, green: 0.906, blue: 0.718) // emerald-300
        case .zai:    Color(red: 0.769, green: 0.710, blue: 0.992) // violet-300
        }
    }

    var shortName: String {
        switch self {
        case .claude: "CC"
        case .codex:  "CX"
        case .zai:    "Z"
        }
    }

    var fiveHourLabel: String {
        switch self {
        case .zai: "Qt"
        default: "5h"
        }
    }

    var weeklyLabel: String { "7d" }

    var keychainAccount: String {
        switch self {
        case .claude: "claude"
        case .codex:  "openai"
        case .zai:    "zai"
        }
    }
}
