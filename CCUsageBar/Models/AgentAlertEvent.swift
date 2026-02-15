import Foundation

enum AgentAlertEventType: String, CaseIterable, Sendable {
    case taskCompleted
    case permissionRequired
    case decisionRequired

    var notificationTitle: String {
        switch self {
        case .taskCompleted:
            return "Agent task completed"
        case .permissionRequired:
            return "Agent permission required"
        case .decisionRequired:
            return "Agent decision required"
        }
    }

    var settingsKey: String {
        switch self {
        case .taskCompleted:
            return "alertTaskCompletedEnabled"
        case .permissionRequired:
            return "alertPermissionRequiredEnabled"
        case .decisionRequired:
            return "alertDecisionRequiredEnabled"
        }
    }
}

struct AgentAlertEvent: Sendable, Equatable {
    let service: ServiceType
    let type: AgentAlertEventType
    let timestamp: Date
    let message: String?
    let sessionID: String?

    var dedupeKey: String {
        let session = sessionID ?? "no-session"
        return "\(service.rawValue)|\(type.rawValue)|\(session)"
    }

    var notificationBody: String {
        guard let message else {
            return defaultBody
        }

        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return defaultBody
        }

        let normalized = trimmed.replacingOccurrences(of: "\n", with: " ")
        if normalized.count > 180 {
            let endIndex = normalized.index(normalized.startIndex, offsetBy: 180)
            return String(normalized[..<endIndex]) + "..."
        }
        return normalized
    }

    private var defaultBody: String {
        switch type {
        case .taskCompleted:
            return "Ready for your next prompt."
        case .permissionRequired:
            return "Agent is waiting for an elevated permission decision."
        case .decisionRequired:
            return "Agent is waiting for your input."
        }
    }
}

