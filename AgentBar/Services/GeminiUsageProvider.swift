import Foundation

struct GeminiLogRecord: Decodable, Sendable {
    let type: String?
    let message: String?
    let timestamp: String?
}

struct GeminiSessionFile: Decodable, Sendable {
    let messages: [GeminiSessionMessage]?
}

struct GeminiSessionMessage: Decodable, Sendable {
    let timestamp: String?
    let type: String?
    let content: GeminiMessageContent?
}

enum GeminiMessageContent: Decodable, Sendable {
    case text(String)
    case parts([GeminiContentPart])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .text(str)
        } else if let parts = try? container.decode([GeminiContentPart].self) {
            self = .parts(parts)
        } else {
            self = .text("")
        }
    }

    var textValue: String {
        switch self {
        case .text(let str): return str
        case .parts(let parts): return parts.compactMap(\.text).joined(separator: " ")
        }
    }
}

struct GeminiContentPart: Decodable, Sendable {
    let text: String?
}

final class GeminiUsageProvider: UsageProviderProtocol, @unchecked Sendable {
    let serviceType: ServiceType = .gemini

    private let logsRootDir: URL
    private let dailyRequestLimit: Double
    private let nowProvider: @Sendable () -> Date
    private let calendar: Calendar
    private let defaults: UserDefaults

    init(
        logsRootDir: URL? = nil,
        dailyRequestLimit: Double = 1_000,
        nowProvider: @escaping @Sendable () -> Date = Date.init,
        defaults: UserDefaults = .standard
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.logsRootDir = logsRootDir ?? home.appendingPathComponent(".gemini/tmp")
        self.dailyRequestLimit = dailyRequestLimit
        self.nowProvider = nowProvider
        self.defaults = defaults

        var pacificCalendar = Calendar(identifier: .gregorian)
        pacificCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        self.calendar = pacificCalendar
    }

    func isConfigured() async -> Bool {
        FileManager.default.fileExists(atPath: logsRootDir.path)
    }

    func fetchUsage() async throws -> UsageData {
        let now = nowProvider()
        let usageEvents = scanUsageEvents(now: now)

        let dayStart = calendar.startOfDay(for: now)
        let dayEvents = usageEvents.filter { $0 >= dayStart && $0 <= now }

        let dayReset = calendar.date(byAdding: .day, value: 1, to: dayStart)

        let incoming = UsageMetric(
            used: Double(dayEvents.count),
            total: dailyRequestLimit,
            unit: .requests,
            resetTime: dayReset
        )
        let metric = resolveMetric(incoming: incoming, cacheKey: "geminiUsageCache.daily", now: now)

        return UsageData(
            service: .gemini,
            fiveHourUsage: metric,
            weeklyUsage: nil,
            lastUpdated: now,
            isAvailable: true
        )
    }

    // MARK: - Usage Caching

    private func resolveMetric(incoming: UsageMetric, cacheKey: String, now: Date) -> UsageMetric {
        let cached = validCachedMetric(forKey: cacheKey, now: now)

        if incoming.used <= 0, let cached, cached.used > 0,
           let cachedReset = cached.resetTime, cachedReset > now {
            return cached
        }

        if incoming.used > 0 {
            saveMetricCache(incoming, forKey: cacheKey)
        }
        return incoming
    }

    private func validCachedMetric(forKey key: String, now: Date) -> UsageMetric? {
        guard defaults.object(forKey: "\(key).used") != nil else { return nil }
        let used = defaults.double(forKey: "\(key).used")
        let total = defaults.object(forKey: "\(key).total") != nil
            ? defaults.double(forKey: "\(key).total") : dailyRequestLimit
        let resetTimestamp = defaults.object(forKey: "\(key).resetTime") as? Double
        let resetTime = resetTimestamp.map { Date(timeIntervalSince1970: $0) }

        if let resetTime, resetTime <= now {
            clearMetricCache(forKey: key)
            return nil
        }
        if used <= 0, resetTime == nil {
            clearMetricCache(forKey: key)
            return nil
        }
        return UsageMetric(used: used, total: total, unit: .requests, resetTime: resetTime)
    }

    private func saveMetricCache(_ metric: UsageMetric, forKey key: String) {
        defaults.set(metric.used, forKey: "\(key).used")
        defaults.set(metric.total, forKey: "\(key).total")
        defaults.set(metric.resetTime?.timeIntervalSince1970, forKey: "\(key).resetTime")
    }

    private func clearMetricCache(forKey key: String) {
        defaults.removeObject(forKey: "\(key).used")
        defaults.removeObject(forKey: "\(key).total")
        defaults.removeObject(forKey: "\(key).resetTime")
    }

    // MARK: - Private

    private func scanUsageEvents(now: Date) -> [Date] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: logsRootDir.path) else { return [] }

        // Keep scans lightweight while still covering the current Pacific day.
        let cutoff = now.addingTimeInterval(-48 * 3600)
        var events: [Date] = []

        guard let enumerator = fm.enumerator(
            at: logsRootDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let decoder = JSONDecoder()

        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent
            let isLogsFile = name == "logs.json"
            let isSessionFile = name.hasPrefix("session-") && fileURL.pathExtension == "json"
            guard isLogsFile || isSessionFile else { continue }

            if let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
               let modDate = attrs[.modificationDate] as? Date,
               modDate < cutoff {
                continue
            }

            guard let data = try? Data(contentsOf: fileURL) else { continue }

            if isLogsFile {
                guard let records = try? decoder.decode([GeminiLogRecord].self, from: data) else { continue }
                for record in records {
                    guard isCountablePrompt(record) else { continue }
                    guard let ts = record.timestamp, let date = DateUtils.parseISO8601(ts) else { continue }
                    events.append(date)
                }
            } else {
                guard let sessionFile = try? decoder.decode(GeminiSessionFile.self, from: data),
                      let messages = sessionFile.messages else { continue }
                for message in messages {
                    guard isCountablePrompt(message) else { continue }
                    guard let ts = message.timestamp, let date = DateUtils.parseISO8601(ts) else { continue }
                    events.append(date)
                }
            }
        }

        return events
    }

    private func isCountablePrompt(_ message: GeminiSessionMessage) -> Bool {
        guard message.type == "user" else { return false }
        guard let content = message.content else { return false }

        let trimmed = content.textValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.hasPrefix("/") { return false }

        let lower = trimmed.lowercased()
        if lower == "exit" || lower == "quit" { return false }

        return true
    }

    private func isCountablePrompt(_ record: GeminiLogRecord) -> Bool {
        guard record.type == "user" else { return false }
        guard let rawMessage = record.message else { return false }

        let trimmed = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.hasPrefix("/") { return false }

        let lower = trimmed.lowercased()
        if lower == "exit" || lower == "quit" { return false }

        return true
    }
}
