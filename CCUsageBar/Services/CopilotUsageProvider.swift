import Foundation

// MARK: - API Response Models

struct CopilotUserResponse: Decodable, Sendable {
    let copilot_plan: String?
    let quota_snapshots: [CopilotQuotaSnapshot]?
}

struct CopilotQuotaSnapshot: Decodable, Sendable {
    let quota_id: String
    let entitlement: Int?
    let remaining: Int?
    let percent_remaining: Double?
    let overage_count: Int?
    let unlimited: Bool?
}

// MARK: - Provider

final class CopilotUsageProvider: UsageProviderProtocol, @unchecked Sendable {
    let serviceType: ServiceType = .copilot

    private let session: URLSession
    private let credentialProvider: @Sendable () -> String?

    static let apiURL = URL(string: "https://api.github.com/copilot_internal/user")!

    init(
        session: URLSession = .shared,
        credentialProvider: (@Sendable () -> String?)? = nil
    ) {
        self.session = session
        self.credentialProvider = credentialProvider ?? {
            KeychainManager.load(account: ServiceType.copilot.keychainAccount)
        }
    }

    func isConfigured() async -> Bool {
        credentialProvider() != nil
    }

    func fetchUsage() async throws -> UsageData {
        guard let pat = credentialProvider() else {
            throw APIError.unauthorized
        }

        var request = URLRequest(url: Self.apiURL, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CCUsageBar", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.httpError(httpResponse.statusCode)
        }

        let apiResponse = try JSONDecoder().decode(CopilotUserResponse.self, from: data)

        // Find the premium_requests quota snapshot
        let premiumSnapshot = apiResponse.quota_snapshots?.first { $0.quota_id == "premium_requests" }

        let used: Double
        let total: Double

        if let snapshot = premiumSnapshot {
            if snapshot.unlimited == true {
                // Unlimited plan — show 0/0
                used = 0
                total = 0
            } else {
                let entitlement = Double(snapshot.entitlement ?? 0)
                let remaining = Double(snapshot.remaining ?? 0)
                used = entitlement - remaining
                total = entitlement
            }
        } else {
            used = 0
            total = 0
        }

        // Reset = 1st of next month 00:00 UTC
        let resetTime = Self.firstOfNextMonthUTC()

        return UsageData(
            service: .copilot,
            fiveHourUsage: UsageMetric(
                used: used,
                total: total,
                unit: .requests,
                resetTime: resetTime
            ),
            weeklyUsage: nil,
            lastUpdated: Date(),
            isAvailable: true
        )
    }

    // MARK: - Helpers

    static func firstOfNextMonthUTC(relativeTo now: Date = Date()) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents([.year, .month], from: now)
        guard let startOfMonth = calendar.date(from: components),
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) else {
            return now
        }
        return nextMonth
    }
}
