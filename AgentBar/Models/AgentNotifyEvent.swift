import Foundation
import CryptoKit

enum AgentNotifyEventType: String, CaseIterable, Sendable {
    case taskCompleted
    case permissionRequired
    case decisionRequired

    var notificationTitle: String {
        switch self {
        case .taskCompleted:
            return "Agent task completed"
        case .permissionRequired, .decisionRequired:
            return "Agent input required"
        }
    }

    var settingsKey: String {
        switch self {
        case .taskCompleted:
            return "notificationTaskCompletedEnabled"
        case .permissionRequired, .decisionRequired:
            return "notificationInputRequiredEnabled"
        }
    }

    var cespCategory: String {
        switch self {
        case .taskCompleted:
            return "task.complete"
        case .permissionRequired, .decisionRequired:
            return "input.required"
        }
    }
}

struct AgentNotifyEvent: Sendable, Equatable {
    let service: ServiceType
    let type: AgentNotifyEventType
    let timestamp: Date
    let message: String?
    let sessionID: String?
    let sourceRecordID: String?

    init(
        service: ServiceType,
        type: AgentNotifyEventType,
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
        if let normalizedSessionID {
            return "\(service.rawValue)|\(type.rawValue)|session:\(normalizedSessionID)"
        }

        if let normalizedMessageForDedupe {
            let digest = SHA256.hash(data: Data(normalizedMessageForDedupe.utf8))
            let token = digest.map { String(format: "%02x", $0) }.joined().prefix(16)
            return "\(service.rawValue)|\(type.rawValue)|message:\(token)"
        }

        let secondBucket = Int(timestamp.timeIntervalSince1970.rounded(.down))
        return "\(service.rawValue)|\(type.rawValue)|ts:\(secondBucket)"
    }

    var cursorID: String {
        hashedCursorID(includeSourceRecordID: true)
    }

    var legacyCursorID: String {
        hashedCursorID(includeSourceRecordID: false)
    }

    private func hashedCursorID(includeSourceRecordID: Bool) -> String {
        let timestampToken = String(format: "%.6f", timestamp.timeIntervalSince1970)
        let base = "\(service.rawValue)|\(type.rawValue)|\(timestampToken)|\(sessionID ?? "")|\(message ?? "")"
        let raw = includeSourceRecordID ? "\(base)|\(sourceRecordID ?? "")" : base
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private var normalizedSessionID: String? {
        guard let sessionID else { return nil }
        let trimmed = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var normalizedMessageForDedupe: String? {
        guard let message else { return nil }
        let normalized = message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return normalized.isEmpty ? nil : normalized.lowercased()
    }

    private var displaySessionLabel: String? {
        guard let normalizedSessionID else { return nil }
        if normalizedSessionID.count <= 32 {
            return normalizedSessionID
        }

        let prefix = normalizedSessionID.prefix(12)
        let suffix = normalizedSessionID.suffix(8)
        return "\(prefix)...\(suffix)"
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

    var notificationSourceTag: String {
        guard let session = displaySessionLabel else {
            return "[\(service.rawValue)]"
        }
        return "[\(service.rawValue) | \(session)]"
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
