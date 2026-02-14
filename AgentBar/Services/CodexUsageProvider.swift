import Foundation

// MARK: - Codex Session Record Models (matches actual ~/.codex/sessions/ JSONL)

struct CodexSessionRecord: Decodable, Sendable {
    let timestamp: String?
    let type: String?
    let payload: CodexPayload?
}

struct CodexPayload: Decodable, Sendable {
    let type: String?
    let info: CodexTokenInfo?
    let rate_limits: CodexRateLimits?
}

struct CodexTokenInfo: Decodable, Sendable {
    let total_token_usage: CodexTokenUsage?
    let last_token_usage: CodexTokenUsage?
}

struct CodexTokenUsage: Decodable, Sendable {
    let input_tokens: Int?
    let output_tokens: Int?
    let cached_input_tokens: Int?
    let reasoning_output_tokens: Int?
    let total_tokens: Int?

    var totalTokens: Int {
        (input_tokens ?? 0) +
        (cached_input_tokens ?? 0) +
        (output_tokens ?? 0) +
        (reasoning_output_tokens ?? 0)
    }
}

struct CodexRateLimits: Decodable, Sendable {
    let primary: CodexRateWindow?
    let secondary: CodexRateWindow?
}

struct CodexRateWindow: Decodable, Sendable {
    let used_percent: Double?
    let window_minutes: Int?
    let resets_at: Int?
}

// MARK: - Provider

final class CodexUsageProvider: UsageProviderProtocol, @unchecked Sendable {
    let serviceType: ServiceType = .codex

    private let sessionsDir: URL
    private let fiveHourTokenLimit: Double
    private let weeklyTokenLimit: Double

    init(
        sessionsDir: URL? = nil,
        fiveHourTokenLimit: Double = 10_000_000,
        weeklyTokenLimit: Double = 100_000_000
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.sessionsDir = sessionsDir ?? home.appendingPathComponent(".codex/sessions")
        self.fiveHourTokenLimit = fiveHourTokenLimit
        self.weeklyTokenLimit = weeklyTokenLimit
    }

    func isConfigured() async -> Bool {
        FileManager.default.fileExists(atPath: sessionsDir.path)
    }

    func fetchUsage() async throws -> UsageData {
        let now = Date()

        // Find the most recent rate_limits from session files
        let latestRateLimits = findLatestRateLimits(now: now)

        var fiveHourUsed: Double = 0
        var weeklyUsed: Double = 0
        var fiveHourResetTime: Date?
        var weeklyResetTime: Date?

        if let rateLimits = latestRateLimits {
            // Use rate_limits percentage, but check if the window has already reset
            if let primary = rateLimits.primary {
                if let resetsAt = primary.resets_at {
                    let resetDate = Date(timeIntervalSince1970: TimeInterval(resetsAt))
                    if resetDate > now {
                        fiveHourUsed = fiveHourTokenLimit * (primary.used_percent ?? 0) / 100.0
                        fiveHourResetTime = resetDate
                    }
                } else {
                    fiveHourUsed = fiveHourTokenLimit * (primary.used_percent ?? 0) / 100.0
                }
            }

            if let secondary = rateLimits.secondary {
                if let resetsAt = secondary.resets_at {
                    let resetDate = Date(timeIntervalSince1970: TimeInterval(resetsAt))
                    if resetDate > now {
                        weeklyUsed = weeklyTokenLimit * (secondary.used_percent ?? 0) / 100.0
                        weeklyResetTime = resetDate
                    }
                } else {
                    weeklyUsed = weeklyTokenLimit * (secondary.used_percent ?? 0) / 100.0
                }
            }
        } else {
            // Fallback: sum tokens from session files
            let (fiveHour, weekly) = sumTokensFromSessions(now: now)
            fiveHourUsed = Double(fiveHour)
            weeklyUsed = Double(weekly)
        }

        return UsageData(
            service: .codex,
            fiveHourUsage: UsageMetric(
                used: fiveHourUsed,
                total: fiveHourTokenLimit,
                unit: .tokens,
                resetTime: fiveHourResetTime
            ),
            weeklyUsage: UsageMetric(
                used: weeklyUsed,
                total: weeklyTokenLimit,
                unit: .tokens,
                resetTime: weeklyResetTime
            ),
            lastUpdated: now,
            isAvailable: true
        )
    }

    // MARK: - Rate Limits Extraction

    private func findLatestRateLimits(now: Date) -> CodexRateLimits? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionsDir.path) else { return nil }

        let recentFiles = findSessionFiles(within: 7 * 24 * 3600, relativeTo: now)
        guard !recentFiles.isEmpty else { return nil }

        // Check the most recent file first (sorted by path descending = most recent date first)
        let sorted = recentFiles.sorted { $0.lastPathComponent > $1.lastPathComponent }

        for file in sorted {
            if let rateLimits = extractLatestRateLimits(from: file) {
                return rateLimits
            }
        }

        return nil
    }

    private func extractLatestRateLimits(from file: URL) -> CodexRateLimits? {
        guard let records = try? JSONLParser.parseFile(file, as: CodexSessionRecord.self) else {
            return nil
        }

        // Find the last event_msg with token_count type that has rate_limits
        var latest: CodexRateLimits?
        for record in records {
            guard record.type == "event_msg",
                  record.payload?.type == "token_count",
                  record.payload?.rate_limits != nil else { continue }
            latest = record.payload?.rate_limits
        }
        return latest
    }

    // MARK: - Token Summing Fallback

    private func sumTokensFromSessions(now: Date) -> (fiveHour: Int, weekly: Int) {
        let fiveHourCutoff = DateUtils.fiveHourWindowStart(relativeTo: now)
        let weeklyCutoff = DateUtils.weeklyWindowStart(relativeTo: now)

        let files = findSessionFiles(within: 7 * 24 * 3600, relativeTo: now)
        var fiveHourTotal = 0
        var weeklyTotal = 0

        for file in files {
            let records = (try? JSONLParser.parseFile(file, as: CodexSessionRecord.self)) ?? []
            for record in records {
                guard record.type == "event_msg",
                      record.payload?.type == "token_count",
                      let info = record.payload?.info,
                      let lastUsage = info.last_token_usage,
                      let ts = record.timestamp,
                      let date = DateUtils.parseISO8601(ts) else { continue }

                let tokens = lastUsage.totalTokens
                if date >= fiveHourCutoff && date <= now {
                    fiveHourTotal += tokens
                }
                if date >= weeklyCutoff && date <= now {
                    weeklyTotal += tokens
                }
            }
        }

        return (fiveHourTotal, weeklyTotal)
    }

    // MARK: - Directory Traversal

    private func findSessionFiles(within seconds: TimeInterval, relativeTo now: Date) -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionsDir.path) else { return [] }

        let cutoff = now.addingTimeInterval(-seconds)
        var results: [URL] = []

        // Recursively enumerate through YYYY/MM/DD/ subdirectories
        guard let enumerator = fm.enumerator(
            at: sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }

            // Skip files not modified recently
            if let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
               let modDate = attrs[.modificationDate] as? Date,
               modDate < cutoff {
                continue
            }

            results.append(fileURL)
        }

        return results
    }
}
