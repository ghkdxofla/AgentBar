import Foundation

private struct ClaudeHookBridgeRecord: Decodable, Sendable {
    let capturedAt: String
    let payloadBase64: String

    enum CodingKeys: String, CodingKey {
        case capturedAt = "captured_at"
        case payloadBase64 = "payload_base64"
    }
}

private struct ClaudeHookPayload: Decodable, Sendable {
    let hookEventName: String?
    let sessionID: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionID = "session_id"
        case message
    }
}

final class ClaudeHookNotifyEventDetector: AgentNotifyEventDetectorProtocol, @unchecked Sendable {
    let serviceType: ServiceType = .claude
    let settingsEnabledKey: String? = "notificationClaudeHookEventsEnabled"

    private let hookEventsFile: URL
    private let fileManager: FileManager

    init(
        hookEventsFile: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.hookEventsFile = hookEventsFile ?? home.appendingPathComponent(".claude/agentbar/hook-events.jsonl")
        self.fileManager = fileManager
    }

    func detectEvents(since: Date, includeBoundary: Bool = false) async -> [AgentNotifyEvent] {
        guard fileManager.fileExists(atPath: hookEventsFile.path) else { return [] }
        guard let records = try? JSONLParser.parseFile(hookEventsFile, as: ClaudeHookBridgeRecord.self) else {
            return []
        }

        var events: [AgentNotifyEvent] = []

        for (index, record) in records.enumerated() {
            guard let capturedAt = DateUtils.parseISO8601(record.capturedAt),
                  passesBoundary(capturedAt, since: since, includeBoundary: includeBoundary),
                  let payloadData = Data(base64Encoded: record.payloadBase64),
                  let payload = try? JSONDecoder().decode(ClaudeHookPayload.self, from: payloadData),
                  let event = mapPayload(payload, capturedAt: capturedAt, lineIndex: index) else {
                continue
            }

            events.append(event)
        }

        return events.sorted { $0.timestamp < $1.timestamp }
    }

    private func mapPayload(
        _ payload: ClaudeHookPayload,
        capturedAt: Date,
        lineIndex: Int
    ) -> AgentNotifyEvent? {
        let eventName = payload.hookEventName ?? ""
        let sourceRecordID = "claude-hook#\(lineIndex)"

        if eventName == "Stop" || eventName == "SubagentStop" {
            return AgentNotifyEvent(
                service: .claude,
                type: .taskCompleted,
                timestamp: capturedAt,
                message: payload.message,
                sessionID: payload.sessionID,
                sourceRecordID: sourceRecordID
            )
        }

        guard eventName == "Notification" else { return nil }
        let message = payload.message ?? ""
        let type: AgentNotifyEventType

        if looksLikePermissionPrompt(message) {
            type = .permissionRequired
        } else if looksLikeDecisionPrompt(message) {
            type = .decisionRequired
        } else if looksLikeTaskCompletion(message) {
            type = .taskCompleted
        } else {
            return nil
        }

        return AgentNotifyEvent(
            service: .claude,
            type: type,
            timestamp: capturedAt,
            message: message,
            sessionID: payload.sessionID,
            sourceRecordID: sourceRecordID
        )
    }

    private func looksLikePermissionPrompt(_ message: String) -> Bool {
        let lower = message.lowercased()
        let englishMarkers = [
            "permission",
            "approve",
            "approval",
            "allow",
            "sandbox",
            "require_escalated",
            "elevated"
        ]
        let koreanMarkers = [
            "권한",
            "승인",
            "허용",
            "퍼미션"
        ]
        return englishMarkers.contains(where: lower.contains) || koreanMarkers.contains(where: message.contains)
    }

    private func looksLikeDecisionPrompt(_ message: String) -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lower = trimmed.lowercased()
        let englishMarkers = [
            "waiting for your input",
            "waiting for input",
            "waiting for your decision",
            "need your decision",
            "would you like",
            "do you want",
            "choose",
            "select"
        ]
        let koreanMarkers = [
            "입력",
            "결정",
            "선택",
            "진행할까요",
            "응답"
        ]

        if trimmed.contains("?") { return true }
        if englishMarkers.contains(where: lower.contains) { return true }
        if koreanMarkers.contains(where: trimmed.contains) { return true }
        return false
    }

    private func looksLikeTaskCompletion(_ message: String) -> Bool {
        let lower = message.lowercased()
        let englishMarkers = [
            "task complete",
            "completed",
            "finished",
            "all done",
            "ready for your next prompt"
        ]
        let koreanMarkers = [
            "작업 완료",
            "완료되었습니다",
            "끝났습니다"
        ]
        return englishMarkers.contains(where: lower.contains) || koreanMarkers.contains(where: message.contains)
    }
}
