import Foundation

// MARK: - Z.ai Quota API Response (actual format)

struct ZaiQuotaResponse: Decodable, Sendable {
    let code: Int?
    let data: ZaiQuotaData?
    let success: Bool?
}

struct ZaiQuotaData: Decodable, Sendable {
    let limits: [ZaiLimit]?
    let level: String?
}

struct ZaiLimit: Decodable, Sendable {
    let type: String
    let usage: Double?          // total capacity
    let currentValue: Double?   // currently used
    let remaining: Double?
    let percentage: Double?
    let nextResetTime: Double?  // epoch ms
    let usageDetails: [ZaiUsageDetail]?
}

struct ZaiUsageDetail: Decodable, Sendable {
    let modelCode: String?
    let usage: Int?
}

// MARK: - Z.ai Model Usage API Response

struct ZaiModelUsageResponse: Decodable, Sendable {
    let code: Int?
    let data: ZaiModelUsageData?
    let success: Bool?
}

struct ZaiModelUsageData: Decodable, Sendable {
    let totalUsage: ZaiTotalUsage?
}

struct ZaiTotalUsage: Decodable, Sendable {
    let totalModelCallCount: Int?
    let totalTokensUsage: Int?
}

// MARK: - Provider

final class ZaiUsageProvider: UsageProviderProtocol, @unchecked Sendable {
    let serviceType: ServiceType = .zai

    private let apiClient: APIClient

    init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
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

        let response: ZaiQuotaResponse = try await fetchWithAuthRetry(
            url: quotaURL,
            apiKey: apiKey
        )

        guard let data = response.data, let limits = data.limits else {
            throw APIError.noData
        }

        // TIME_LIMIT is the active rate limit (requests per window)
        let timeLimit = limits.first { $0.type == "TIME_LIMIT" }
        let fiveHourUsed = timeLimit?.currentValue ?? 0
        let fiveHourTotal = timeLimit?.usage ?? 0
        let nextReset: Date? = timeLimit?.nextResetTime.map {
            Date(timeIntervalSince1970: $0 / 1000)
        }

        // Weekly: fetch model-usage for 7 days
        let weeklyUsage = await fetchWeeklyUsage(apiKey: apiKey, now: now)

        return UsageData(
            service: .zai,
            fiveHourUsage: UsageMetric(
                used: fiveHourUsed,
                total: fiveHourTotal,
                unit: .requests,
                resetTime: nextReset
            ),
            weeklyUsage: UsageMetric(
                used: Double(weeklyUsage.calls),
                total: fiveHourTotal,
                unit: .requests,
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

    private func fetchWeeklyUsage(apiKey: String, now: Date) async -> (calls: Int, tokens: Int) {
        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 3600)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let startTime = formatter.string(from: sevenDaysAgo)
        let endTime = formatter.string(from: now)

        // URL-encode the datetime strings
        guard let startEncoded = startTime.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let endEncoded = endTime.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.z.ai/api/monitor/usage/model-usage?startTime=\(startEncoded)&endTime=\(endEncoded)") else {
            return (0, 0)
        }

        do {
            let response: ZaiModelUsageResponse = try await fetchWithAuthRetry(url: url, apiKey: apiKey)
            let total = response.data?.totalUsage
            return (total?.totalModelCallCount ?? 0, total?.totalTokensUsage ?? 0)
        } catch {
            return (0, 0)
        }
    }
}
