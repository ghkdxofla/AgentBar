import Foundation

struct GeminiLogRecord: Decodable, Sendable {
    let type: String?
    let message: String?
    let timestamp: String?
}

final class GeminiUsageProvider: UsageProviderProtocol, @unchecked Sendable {
    let serviceType: ServiceType = .gemini

    private let logsRootDir: URL
    private let dailyRequestLimit: Double
    private let nowProvider: @Sendable () -> Date
    private let calendar: Calendar

    init(
        logsRootDir: URL? = nil,
        dailyRequestLimit: Double = 1_000,
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.logsRootDir = logsRootDir ?? home.appendingPathComponent(".gemini/tmp")
        self.dailyRequestLimit = dailyRequestLimit
        self.nowProvider = nowProvider

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

        return UsageData(
            service: .gemini,
            fiveHourUsage: UsageMetric(
                used: Double(dayEvents.count),
                total: dailyRequestLimit,
                unit: .requests,
                resetTime: dayReset
            ),
            weeklyUsage: nil,
            lastUpdated: now,
            isAvailable: true
        )
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
            guard fileURL.lastPathComponent == "logs.json" else { continue }

            if let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
               let modDate = attrs[.modificationDate] as? Date,
               modDate < cutoff {
                continue
            }

            guard let data = try? Data(contentsOf: fileURL),
                  let records = try? decoder.decode([GeminiLogRecord].self, from: data) else {
                continue
            }

            for record in records {
                guard isCountablePrompt(record) else { continue }
                guard let ts = record.timestamp, let date = DateUtils.parseISO8601(ts) else { continue }
                events.append(date)
            }
        }

        return events
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
