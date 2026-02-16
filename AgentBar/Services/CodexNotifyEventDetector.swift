import Foundation

private struct CodexNotifySessionRecord: Decodable, Sendable {
    let timestamp: String?
    let type: String?
    let payload: CodexNotifyPayload?
}

private struct CodexNotifyPayload: Decodable, Sendable {
    let type: String?
    let message: String?
    let arguments: String?
}

final class CodexNotifyEventDetector: AgentNotifyEventDetectorProtocol, @unchecked Sendable {
    let serviceType: ServiceType = .codex
    let settingsEnabledKey: String? = "notificationCodexEventsEnabled"

    private let sessionsDir: URL
    private let fileManager: FileManager

    init(
        sessionsDir: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.sessionsDir = sessionsDir ?? home.appendingPathComponent(".codex/sessions")
        self.fileManager = fileManager
    }

    func detectEvents(since: Date, includeBoundary: Bool = false) async -> [AgentNotifyEvent] {
        guard fileManager.fileExists(atPath: sessionsDir.path) else { return [] }

        let files = findRecentSessionFiles(since: since)
        guard !files.isEmpty else { return [] }

        var events: [AgentNotifyEvent] = []
        for file in files {
            events.append(contentsOf: extractEvents(from: file, since: since, includeBoundary: includeBoundary))
        }

        return events.sorted { $0.timestamp < $1.timestamp }
    }

    private func extractEvents(from file: URL, since: Date, includeBoundary: Bool) -> [AgentNotifyEvent] {
        let sessionID = file.deletingPathExtension().lastPathComponent
        guard let records = try? JSONLParser.parseFile(file, as: CodexNotifySessionRecord.self) else {
            return []
        }

        var events: [AgentNotifyEvent] = []

        for (index, record) in records.enumerated() {
            guard let timestamp = record.timestamp,
                  let date = DateUtils.parseISO8601(timestamp),
                  passesBoundary(date, since: since, includeBoundary: includeBoundary) else { continue }

            guard let payload = record.payload else { continue }
            let sourceRecordID = "\(sessionID)#\(index)"
            if let event = mapRecord(
                recordType: record.type,
                payload: payload,
                date: date,
                sessionID: sessionID,
                sourceRecordID: sourceRecordID
            ) {
                events.append(event)
            }
        }

        return events
    }

    private func mapRecord(
        recordType: String?,
        payload: CodexNotifyPayload,
        date: Date,
        sessionID: String,
        sourceRecordID: String
    ) -> AgentNotifyEvent? {
        if recordType == "event_msg" {
            if payload.type == "task_complete" {
                return AgentNotifyEvent(
                    service: .codex,
                    type: .taskCompleted,
                    timestamp: date,
                    message: nil,
                    sessionID: sessionID,
                    sourceRecordID: sourceRecordID
                )
            }

            if payload.type == "agent_message",
               let message = payload.message,
               looksLikeDecisionPrompt(message) {
                return AgentNotifyEvent(
                    service: .codex,
                    type: .decisionRequired,
                    timestamp: date,
                    message: message,
                    sessionID: sessionID,
                    sourceRecordID: sourceRecordID
                )
            }
        }

        if recordType == "response_item",
           payload.type == "function_call",
           isEscalationRequired(payload.arguments) {
            return AgentNotifyEvent(
                service: .codex,
                type: .permissionRequired,
                timestamp: date,
                message: "Codex requested elevated command permissions.",
                sessionID: sessionID,
                sourceRecordID: sourceRecordID
            )
        }

        return nil
    }

    private func isEscalationRequired(_ arguments: String?) -> Bool {
        guard let arguments else { return false }

        let compact = arguments.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        if compact.contains("\"sandbox_permissions\":\"require_escalated\"") {
            return true
        }

        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let permission = object["sandbox_permissions"] as? String else {
            return false
        }

        return permission == "require_escalated"
    }

    private func looksLikeDecisionPrompt(_ message: String) -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lower = trimmed.lowercased()
        let englishMarkers = [
            "would you like",
            "do you want",
            "which option",
            "choose",
            "select",
            "should i",
            "proceed"
        ]
        let koreanMarkers = [
            "선택",
            "승인",
            "진행",
            "어떻게",
            "원해"
        ]

        if trimmed.contains("?") { return true }
        if englishMarkers.contains(where: lower.contains) { return true }
        if koreanMarkers.contains(where: trimmed.contains) { return true }
        return false
    }

    private func findRecentSessionFiles(since: Date) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let cutoff = since.addingTimeInterval(-120)
        var files: [URL] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }

            if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
               let modDate = attrs[.modificationDate] as? Date,
               modDate < cutoff {
                continue
            }

            files.append(fileURL)
        }

        return files.sorted { $0.path < $1.path }
    }
}
