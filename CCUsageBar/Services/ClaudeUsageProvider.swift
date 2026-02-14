import Foundation
import Security

// MARK: - API Response Models

struct ClaudeOAuthCredentials: Decodable, Sendable {
    let claudeAiOauth: ClaudeOAuthToken
}

struct ClaudeOAuthToken: Decodable, Sendable {
    let accessToken: String
}

struct ClaudeUsageResponse: Decodable, Sendable {
    let five_hour: ClaudeUsageWindow?
    let seven_day: ClaudeUsageWindow?
}

struct ClaudeUsageWindow: Decodable, Sendable {
    let utilization: Double
    let resets_at: String?
}

// MARK: - Provider

final class ClaudeUsageProvider: UsageProviderProtocol, @unchecked Sendable {
    let serviceType: ServiceType = .claude

    private let session: URLSession
    private let credentialProvider: @Sendable () -> String?

    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    init(
        session: URLSession = .shared,
        credentialProvider: (@Sendable () -> String?)? = nil
    ) {
        self.session = session
        self.credentialProvider = credentialProvider ?? Self.readKeychainToken
    }

    func isConfigured() async -> Bool {
        credentialProvider() != nil
    }

    func fetchUsage() async throws -> UsageData {
        guard let token = credentialProvider() else {
            throw APIError.unauthorized
        }

        var request = URLRequest(url: Self.usageURL, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

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

        let usageResponse = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)

        let fiveHour = usageResponse.five_hour
        let sevenDay = usageResponse.seven_day

        return UsageData(
            service: .claude,
            fiveHourUsage: UsageMetric(
                used: fiveHour?.utilization ?? 0,
                total: 100,
                unit: .percent,
                resetTime: fiveHour?.resets_at.flatMap { DateUtils.parseISO8601($0) }
            ),
            weeklyUsage: UsageMetric(
                used: sevenDay?.utilization ?? 0,
                total: 100,
                unit: .percent,
                resetTime: sevenDay?.resets_at.flatMap { DateUtils.parseISO8601($0) }
            ),
            lastUpdated: Date(),
            isAvailable: true
        )
    }

    // MARK: - Keychain Access

    private static func readKeychainToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }

        guard let creds = try? JSONDecoder().decode(ClaudeOAuthCredentials.self, from: data) else {
            return nil
        }
        return creds.claudeAiOauth.accessToken
    }
}
