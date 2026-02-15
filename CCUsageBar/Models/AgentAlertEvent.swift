import Foundation
import CryptoKit

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
    let sourceRecordID: String?

    init(
        service: ServiceType,
        type: AgentAlertEventType,
        timestamp: Date,
        message: String?,
        sessionID: String?,
        sourceRecordID: String? = nil
    ) {
        self.service = service
        self.type = type
        self.timestamp = timestamp
        self.message = message
        self.sessionID = sessionID
        self.sourceRecordID = sourceRecordID
    }

    var dedupeKey: String {
        let session = sessionID ?? "no-session"
        return "\(service.rawValue)|\(type.rawValue)|\(session)"
    }

    var cursorID: String {
        let timestampToken = String(format: "%.6f", timestamp.timeIntervalSince1970)
        let raw = "\(service.rawValue)|\(type.rawValue)|\(timestampToken)|\(sessionID ?? "")|\(message ?? "")|\(sourceRecordID ?? "")"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
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

    var redactedNotificationBody: String {
        defaultBody
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
