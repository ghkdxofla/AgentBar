import Foundation

struct ClaudeMessageRecord: Decodable, Sendable {
    let type: String?
    let timestamp: String?
    let sessionId: String?
    let costUSD: Double?
    let usage: ClaudeTokenUsage?
    let model: String?

    // Support sub-agent messages that have nested message.usage
    let message: ClaudeNestedMessage?
}

struct ClaudeNestedMessage: Decodable, Sendable {
    let id: String?
    let usage: ClaudeTokenUsage?
}

struct ClaudeTokenUsage: Decodable, Sendable {
    let input_tokens: Int?
    let output_tokens: Int?
    let cache_read_input_tokens: Int?
    let cache_creation_input_tokens: Int?

    /// All tokens summed (ccusage-compatible formula)
    var totalTokens: Int {
        (input_tokens ?? 0)
        + (output_tokens ?? 0)
        + (cache_creation_input_tokens ?? 0)
        + (cache_read_input_tokens ?? 0)
    }
}

final class ClaudeUsageProvider: UsageProviderProtocol, @unchecked Sendable {
    let serviceType: ServiceType = .claude

    private let projectsDir: URL
    private let fiveHourTokenLimit: Double
    private let weeklyTokenLimit: Double
    private let nowProvider: @Sendable () -> Date

    init(
        projectsDir: URL? = nil,
        fiveHourTokenLimit: Double = 45_000_000,
        weeklyTokenLimit: Double = 500_000_000,
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.projectsDir = projectsDir ?? home.appendingPathComponent(".claude/projects")
        self.fiveHourTokenLimit = fiveHourTokenLimit
        self.weeklyTokenLimit = weeklyTokenLimit
        self.nowProvider = nowProvider
    }

    func isConfigured() async -> Bool {
        FileManager.default.fileExists(atPath: projectsDir.path)
    }

    func fetchUsage() async throws -> UsageData {
        let now = nowProvider()
        let records = try scanRecentRecords(now: now)
        let sessionStarts = earliestSessionTimestamps(from: records)

        // Deduplicate by message ID — keep only the last record per ID
        let deduplicated = deduplicateByMessageID(records)

        let fiveHourRecords = deduplicated.filter { rec in
            guard let ts = rec.timestamp, let date = DateUtils.parseISO8601(ts) else { return false }
            return DateUtils.isWithinFiveHourWindow(date, relativeTo: now)
        }

        let weeklyRecords = deduplicated.filter { rec in
            guard let ts = rec.timestamp, let date = DateUtils.parseISO8601(ts) else { return false }
            return DateUtils.isWithinWeeklyWindow(date, relativeTo: now)
        }

        let fiveHourTokens = sumTokens(from: fiveHourRecords)
        let weeklyTokens = sumTokens(from: weeklyRecords)

        let fiveHourReset = sessionBasedFiveHourReset(
            from: fiveHourRecords,
            sessionStarts: sessionStarts,
            now: now
        )
        let weeklyReset = earliestTimestamp(from: weeklyRecords)
            .map { $0.addingTimeInterval(DateUtils.weeklyInterval) }

        return UsageData(
            service: .claude,
            fiveHourUsage: UsageMetric(
                used: Double(fiveHourTokens),
                total: fiveHourTokenLimit,
                unit: .tokens,
                resetTime: fiveHourReset
            ),
            weeklyUsage: UsageMetric(
                used: Double(weeklyTokens),
                total: weeklyTokenLimit,
                unit: .tokens,
                resetTime: weeklyReset
            ),
            lastUpdated: now,
            isAvailable: true
        )
    }

    // MARK: - Private

    private func scanRecentRecords(now: Date) throws -> [ClaudeMessageRecord] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: projectsDir.path) else {
            return []
        }

        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 3600)
        var allRecords: [ClaudeMessageRecord] = []

        let projectDirs = try fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        for dir in projectDirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            let files = try fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            for file in files {
                guard file.pathExtension == "jsonl" else { continue }

                if let attrs = try? fm.attributesOfItem(atPath: file.path),
                   let modDate = attrs[.modificationDate] as? Date,
                   modDate < sevenDaysAgo {
                    continue
                }

                let records = try JSONLParser.parseFile(file, as: ClaudeMessageRecord.self)
                allRecords.append(contentsOf: records)
            }
        }

        return allRecords
    }

    private func deduplicateByMessageID(_ records: [ClaudeMessageRecord]) -> [ClaudeMessageRecord] {
        var lastByID: [String: ClaudeMessageRecord] = [:]
        var noIDRecords: [ClaudeMessageRecord] = []

        for record in records {
            guard record.type == "assistant" else { continue }
            if let msgID = record.message?.id {
                lastByID[msgID] = record
            } else {
                noIDRecords.append(record)
            }
        }

        return Array(lastByID.values) + noIDRecords
    }

    private func earliestTimestamp(from records: [ClaudeMessageRecord]) -> Date? {
        records.compactMap { $0.timestamp }
            .compactMap { DateUtils.parseISO8601($0) }
            .min()
    }

    private func sumTokens(from records: [ClaudeMessageRecord]) -> Int {
        records.reduce(0) { sum, record in
            sum + (record.message?.usage?.totalTokens ?? 0)
        }
    }

    private func earliestSessionTimestamps(from records: [ClaudeMessageRecord]) -> [String: Date] {
        var starts: [String: Date] = [:]

        for record in records {
            guard let sessionID = record.sessionId,
                  let ts = record.timestamp,
                  let date = DateUtils.parseISO8601(ts)
            else {
                continue
            }

            if let existing = starts[sessionID] {
                if date < existing {
                    starts[sessionID] = date
                }
            } else {
                starts[sessionID] = date
            }
        }

        return starts
    }

    private func sessionBasedFiveHourReset(
        from records: [ClaudeMessageRecord],
        sessionStarts: [String: Date],
        now: Date
    ) -> Date? {
        guard !records.isEmpty else { return nil }

        let candidates = records.compactMap { record -> Date? in
            guard let sessionID = record.sessionId,
                  let start = sessionStarts[sessionID]
            else {
                return nil
            }

            return DateUtils.nextResetAligned(
                to: start,
                windowDuration: DateUtils.fiveHourInterval,
                relativeTo: now
            )
        }

        // Use the earliest upcoming session reset so we don't overstate remaining time.
        if let sessionReset = candidates.min() {
            return sessionReset
        }

        // Fallback for logs without session metadata.
        return earliestTimestamp(from: records)
            .map { $0.addingTimeInterval(DateUtils.fiveHourInterval) }
    }
}
