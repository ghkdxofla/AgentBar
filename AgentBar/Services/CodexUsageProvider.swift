import Foundation

// MARK: - OpenAI Usage API Response Models

struct OpenAIUsageResponse: Decodable, Sendable {
    let object: String?
    let data: [OpenAIBucket]?
    let has_more: Bool?
}

struct OpenAIBucket: Decodable, Sendable {
    let object: String?
    let start_time: Int?
    let end_time: Int?
    let results: [OpenAIUsageResult]?
}

struct OpenAIUsageResult: Decodable, Sendable {
    let object: String?
    let input_tokens: Int?
    let output_tokens: Int?
    let num_model_requests: Int?
    let model: String?
}

struct OpenAICostResponse: Decodable, Sendable {
    let object: String?
    let data: [OpenAICostBucket]?
}

struct OpenAICostBucket: Decodable, Sendable {
    let start_time: Int?
    let end_time: Int?
    let results: [OpenAICostResult]?
}

struct OpenAICostResult: Decodable, Sendable {
    let amount: OpenAICostAmount?
    let line_item: String?
}

struct OpenAICostAmount: Decodable, Sendable {
    let value: Double?
    let currency: String?
}

// MARK: - Provider

final class CodexUsageProvider: UsageProviderProtocol, @unchecked Sendable {
    let serviceType: ServiceType = .codex

    private let apiClient: APIClient
    private let sessionsDir: URL
    private let fiveHourDollarLimit: Double
    private let weeklyDollarLimit: Double

    init(
        apiClient: APIClient = APIClient(),
        sessionsDir: URL? = nil,
        fiveHourDollarLimit: Double = 5.0,
        weeklyDollarLimit: Double = 50.0
    ) {
        self.apiClient = apiClient
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.sessionsDir = sessionsDir ?? home.appendingPathComponent(".codex/sessions")
        self.fiveHourDollarLimit = fiveHourDollarLimit
        self.weeklyDollarLimit = weeklyDollarLimit
    }

    func isConfigured() async -> Bool {
        KeychainManager.load(account: ServiceType.codex.keychainAccount) != nil
            || FileManager.default.fileExists(atPath: sessionsDir.path)
    }

    func fetchUsage() async throws -> UsageData {
        let now = Date()
        var weeklyCost: Double = 0
        var fiveHourCost: Double = 0

        // Try API first
        if let apiKey = KeychainManager.load(account: ServiceType.codex.keychainAccount) {
            weeklyCost = await fetchWeeklyCostFromAPI(apiKey: apiKey, now: now)
        }

        // Local session files for 5-hour precision
        let localFiveHour = parseLocalSessions(now: now, window: .fiveHour)
        let localWeekly = parseLocalSessions(now: now, window: .weekly)

        // Use local data for 5-hour (more precise), API or local for weekly
        fiveHourCost = localFiveHour
        if weeklyCost == 0 {
            weeklyCost = localWeekly
        }

        return UsageData(
            service: .codex,
            fiveHourUsage: UsageMetric(
                used: fiveHourCost,
                total: fiveHourDollarLimit,
                unit: .dollars,
                resetTime: DateUtils.nextResetTime(
                    from: DateUtils.fiveHourWindowStart(relativeTo: now),
                    windowDuration: DateUtils.fiveHourInterval
                )
            ),
            weeklyUsage: UsageMetric(
                used: weeklyCost,
                total: weeklyDollarLimit,
                unit: .dollars,
                resetTime: nil
            ),
            lastUpdated: now,
            isAvailable: true
        )
    }

    // MARK: - API

    private func fetchWeeklyCostFromAPI(apiKey: String, now: Date) async -> Double {
        let sevenDaysAgo = Int(now.addingTimeInterval(-7 * 24 * 3600).timeIntervalSince1970)
        guard let url = URL(string: "https://api.openai.com/v1/organization/costs?start_time=\(sevenDaysAgo)&bucket_width=1d&limit=7") else {
            return 0
        }

        do {
            let response: OpenAICostResponse = try await apiClient.get(
                url: url,
                headers: [
                    "Authorization": "Bearer \(apiKey)",
                    "Content-Type": "application/json"
                ]
            )
            return response.data?
                .flatMap { $0.results ?? [] }
                .compactMap { $0.amount?.value }
                .reduce(0, +) ?? 0
        } catch {
            return 0
        }
    }

    // MARK: - Local Session Parsing

    private enum Window {
        case fiveHour, weekly
    }

    private func parseLocalSessions(now: Date, window: Window) -> Double {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionsDir.path) else { return 0 }

        let cutoff: Date
        switch window {
        case .fiveHour: cutoff = DateUtils.fiveHourWindowStart(relativeTo: now)
        case .weekly: cutoff = DateUtils.weeklyWindowStart(relativeTo: now)
        }

        guard let files = try? fm.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var totalCost: Double = 0

        for file in files where file.pathExtension == "jsonl" {
            if let attrs = try? fm.attributesOfItem(atPath: file.path),
               let modDate = attrs[.modificationDate] as? Date,
               modDate < cutoff {
                continue
            }

            let records = (try? JSONLParser.parseFile(file, as: CodexSessionRecord.self)) ?? []
            for record in records {
                guard let ts = record.timestamp,
                      let date = DateUtils.parseISO8601(ts),
                      date >= cutoff, date <= now else { continue }
                totalCost += record.costUSD ?? 0
            }
        }

        return totalCost
    }
}

// MARK: - Local Session Record

struct CodexSessionRecord: Decodable, Sendable {
    let type: String?
    let timestamp: String?
    let costUSD: Double?
    let usage: CodexTokenUsage?
}

struct CodexTokenUsage: Decodable, Sendable {
    let input_tokens: Int?
    let output_tokens: Int?

    var totalTokens: Int {
        (input_tokens ?? 0) + (output_tokens ?? 0)
    }
}
