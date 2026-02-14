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

        // TIME_LIMIT is the active rate limit (requests per monthly window)
        let timeLimit = limits.first { $0.type == "TIME_LIMIT" }
        let quotaUsed = timeLimit?.currentValue ?? 0
        let quotaTotal = timeLimit?.usage ?? 0
        let nextReset: Date? = timeLimit?.nextResetTime.map {
            Date(timeIntervalSince1970: $0 / 1000)
        }

        return UsageData(
            service: .zai,
            fiveHourUsage: UsageMetric(
                used: quotaUsed,
                total: quotaTotal,
                unit: .requests,
                resetTime: nextReset
            ),
            weeklyUsage: nil,
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
