import Foundation

// MARK: - Z.ai API Response Models

struct ZaiQuotaResponse: Decodable, Sendable {
    let data: ZaiQuotaData?
}

struct ZaiQuotaData: Decodable, Sendable {
    let planName: String?
    let limits: [ZaiLimit]?
    let usageDetails: [ZaiUsageDetail]?
}

struct ZaiLimit: Decodable, Sendable {
    let type: String
    let used: Double
    let total: Double
    let nextResetTime: Double? // epoch ms
}

struct ZaiUsageDetail: Decodable, Sendable {
    let model: String?
    let tokens: Int?
    let calls: Int?
}

// MARK: - Provider

final class ZaiUsageProvider: UsageProviderProtocol, @unchecked Sendable {
    let serviceType: ServiceType = .zai

    private let apiClient: APIClient
    private let weeklyTokenLimit: Double

    init(
        apiClient: APIClient = APIClient(),
        weeklyTokenLimit: Double = 15_000_000
    ) {
        self.apiClient = apiClient
        self.weeklyTokenLimit = weeklyTokenLimit
    }

    func isConfigured() async -> Bool {
        KeychainManager.load(account: ServiceType.zai.keychainAccount) != nil
    }

    func fetchUsage() async throws -> UsageData {
        guard let apiKey = KeychainManager.load(account: ServiceType.zai.keychainAccount) else {
            throw APIError.unauthorized
        }

        let quotaURL = URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!
        let now = Date()

        // Try Bearer first, then raw key on 401
        let response: ZaiQuotaResponse = try await fetchWithAuthRetry(
            url: quotaURL,
            apiKey: apiKey
        )

        guard let data = response.data, let limits = data.limits else {
            throw APIError.noData
        }

        // Extract token limit (5-hour window)
        let tokenLimit = limits.first { $0.type == "TOKENS_LIMIT" }
        let fiveHourUsed = tokenLimit?.used ?? 0
        let fiveHourTotal = tokenLimit?.total ?? 0
        let nextReset: Date? = tokenLimit?.nextResetTime.map {
            Date(timeIntervalSince1970: $0 / 1000)
        }

        // Weekly: fetch model-usage for 7 days
        let weeklyTokens = await fetchWeeklyTokens(apiKey: apiKey, now: now)

        return UsageData(
            service: .zai,
            fiveHourUsage: UsageMetric(
                used: fiveHourUsed,
                total: fiveHourTotal,
                unit: .tokens,
                resetTime: nextReset
            ),
            weeklyUsage: UsageMetric(
                used: Double(weeklyTokens),
                total: weeklyTokenLimit,
                unit: .tokens,
                resetTime: nil
            ),
            lastUpdated: now,
            isAvailable: true
        )
    }

    // MARK: - Private

    private func fetchWithAuthRetry<T: Decodable & Sendable>(url: URL, apiKey: String) async throws -> T {
        // Try Bearer token first
        do {
            let result: T = try await apiClient.get(
                url: url,
                headers: [
                    "Authorization": "Bearer \(apiKey)",
                    "Accept": "application/json",
                    "Accept-Language": "en-US,en"
                ]
            )
            return result
        } catch APIError.unauthorized {
            // Retry with raw key
            return try await apiClient.get(
                url: url,
                headers: [
                    "Authorization": apiKey,
                    "Accept": "application/json",
                    "Accept-Language": "en-US,en"
                ]
            )
        }
    }

    private func fetchWeeklyTokens(apiKey: String, now: Date) async -> Int {
        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 3600)
        let startMs = Int(sevenDaysAgo.timeIntervalSince1970 * 1000)
        let endMs = Int(now.timeIntervalSince1970 * 1000)

        guard let url = URL(string: "https://api.z.ai/api/monitor/usage/model-usage?startTime=\(startMs)&endTime=\(endMs)") else {
            return 0
        }

        struct ModelUsageResponse: Decodable {
            let data: [ZaiUsageDetail]?
        }

        do {
            let response: ModelUsageResponse = try await fetchWithAuthRetry(url: url, apiKey: apiKey)
            return response.data?.compactMap(\.tokens).reduce(0, +) ?? 0
        } catch {
            return 0
        }
    }
}
