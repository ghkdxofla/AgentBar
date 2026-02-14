import Foundation

struct ClaudeMessageRecord: Decodable, Sendable {
    let type: String?
    let timestamp: String?
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

    /// Rate-limit relevant tokens only: input + output (cache reads are free)
    var rateLimitTokens: Int {
        (input_tokens ?? 0) + (output_tokens ?? 0)
    }
}

struct StatsCacheEntry: Decodable, Sendable {
    let totalCost: Double?
    let totalInputTokens: Int?
    let totalOutputTokens: Int?
    let totalCacheReadTokens: Int?
    let totalCacheWriteTokens: Int?
}

final class ClaudeUsageProvider: UsageProviderProtocol, @unchecked Sendable {
    let serviceType: ServiceType = .claude

    private let projectsDir: URL
    private let statsCachePath: URL
    private let fiveHourTokenLimit: Double
    private let weeklyTokenLimit: Double

    init(
        projectsDir: URL? = nil,
        statsCachePath: URL? = nil,
        fiveHourTokenLimit: Double = 500_000,
        weeklyTokenLimit: Double = 10_000_000
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.projectsDir = projectsDir ?? home.appendingPathComponent(".claude/projects")
        self.statsCachePath = statsCachePath ?? home.appendingPathComponent(".claude/stats-cache.json")
        self.fiveHourTokenLimit = fiveHourTokenLimit
        self.weeklyTokenLimit = weeklyTokenLimit
    }

    func isConfigured() async -> Bool {
        FileManager.default.fileExists(atPath: projectsDir.path)
    }

    func fetchUsage() async throws -> UsageData {
        let now = Date()
        let records = try scanRecentRecords(now: now)

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

        let fiveHourTokens = totalTokens(from: fiveHourRecords)
        let weeklyTokens = totalTokens(from: weeklyRecords)

        return UsageData(
            service: .claude,
            fiveHourUsage: UsageMetric(
                used: Double(fiveHourTokens),
                total: fiveHourTokenLimit,
                unit: .tokens,
                resetTime: DateUtils.nextResetTime(
                    from: DateUtils.fiveHourWindowStart(relativeTo: now),
                    windowDuration: DateUtils.fiveHourInterval
                )
            ),
            weeklyUsage: UsageMetric(
                used: Double(weeklyTokens),
                total: weeklyTokenLimit,
                unit: .tokens,
                resetTime: DateUtils.nextResetTime(
                    from: DateUtils.weeklyWindowStart(relativeTo: now),
                    windowDuration: DateUtils.weeklyInterval
                )
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

        // Enumerate project directories
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

                // Skip files not modified in the last 7 days
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

    /// Streaming causes duplicate records with the same message ID.
    /// Keep only the last occurrence of each message ID.
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

    private func totalTokens(from records: [ClaudeMessageRecord]) -> Int {
        records.reduce(0) { sum, record in
            let nested = record.message?.usage?.rateLimitTokens ?? 0
            return sum + nested
        }
    }
}
