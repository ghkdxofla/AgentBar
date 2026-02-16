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
    private let credentialProvider: @Sendable () -> String?

    /// Minimum cache TTL to avoid excessive API requests (Z.ai is API-based).
    static let minCacheTTL: TimeInterval = 60
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedResponse: UsageData?
    nonisolated(unsafe) private static var cachedAt: Date?

    init(
        apiClient: APIClient = APIClient(),
        credentialProvider: (@Sendable () -> String?)? = nil
    ) {
        self.apiClient = apiClient
        self.credentialProvider = credentialProvider ?? {
            KeychainManager.load(account: ServiceType.zai.keychainAccount)
        }
    }

    func isConfigured() async -> Bool {
        credentialProvider() != nil
    }

    /// Returns cached response if within minimum TTL, nil otherwise.
    static func cachedIfFresh(now: Date = Date()) -> UsageData? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let cached = cachedResponse,
              let cachedTime = cachedAt,
              now.timeIntervalSince(cachedTime) < minCacheTTL else {
            return nil
        }
        return cached
    }

    /// Stores a response in the cache.
    static func updateCache(_ data: UsageData, now: Date = Date()) {
        cacheLock.lock()
        cachedResponse = data
        cachedAt = now
        cacheLock.unlock()
    }

    func fetchUsage() async throws -> UsageData {
        if let cached = Self.cachedIfFresh() {
            return cached
        }

        guard let apiKey = credentialProvider() else {
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

        let planName = data.level.map { Self.capitalizedPlanName($0) }

        let result = UsageData(
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
            isAvailable: true,
            planName: planName
        )

        Self.updateCache(result, now: now)
        return result
    }

    // MARK: - Helpers

    static func capitalizedPlanName(_ raw: String) -> String {
        guard !raw.isEmpty else { return raw }
        return raw.prefix(1).uppercased() + raw.dropFirst()
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
