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

        // TOKENS_LIMIT = 5h prompt window (percent-based, no used/total counts)
        let tokensLimit = limits.first { $0.type == "TOKENS_LIMIT" }
        let fiveHourPercent = tokensLimit?.percentage ?? 0
        let fiveHourReset: Date? = tokensLimit?.nextResetTime.map {
            Date(timeIntervalSince1970: $0 / 1000)
        }

        // TIME_LIMIT = monthly MCP allocation (request count)
        let timeLimit = limits.first { $0.type == "TIME_LIMIT" }
        let mcpUsed = timeLimit?.currentValue ?? 0
        let mcpTotal = timeLimit?.usage ?? 0
        let mcpReset: Date? = timeLimit?.nextResetTime.map {
            Date(timeIntervalSince1970: $0 / 1000)
        }

        return UsageData(
            service: .zai,
            fiveHourUsage: UsageMetric(
                used: fiveHourPercent,
                total: 100,
                unit: .percent,
                resetTime: fiveHourReset
            ),
            weeklyUsage: UsageMetric(
                used: mcpUsed,
                total: mcpTotal,
                unit: .requests,
                resetTime: mcpReset
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

}
