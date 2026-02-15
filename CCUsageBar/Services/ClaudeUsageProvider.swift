import Foundation

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
    private let defaults: UserDefaults

    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private static let keychainService = "Claude Code-credentials"
    private static let tokenCacheLock = NSLock()
    private static let defaultCacheTTL: TimeInterval = 60
    private static let securityCLITimeout: TimeInterval = 2
    nonisolated(unsafe) private static var cachedToken: String?
    nonisolated(unsafe) private static var tokenLastLookupAt: Date?
    typealias SecurityCLIProcessRuntime = CLIProcessRuntime
    nonisolated(unsafe) static var securityCLIRunner: @Sendable (_ timeout: TimeInterval) -> String? = { timeout in
        runSecurityCLICommand(timeout: timeout)
    }

    init(
        session: URLSession = .shared,
        credentialProvider: (@Sendable () -> String?)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.session = session
        self.credentialProvider = credentialProvider ?? { Self.readKeychainTokenViaCLI() }
        self.defaults = defaults
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

        let fiveHour = resolveMetric(window: usageResponse.five_hour, cacheKey: "claudeUsageCache.fiveHour")
        let sevenDay = resolveMetric(window: usageResponse.seven_day, cacheKey: "claudeUsageCache.sevenDay")

        return UsageData(
            service: .claude,
            fiveHourUsage: fiveHour,
            weeklyUsage: sevenDay,
            lastUpdated: Date(),
            isAvailable: true
        )
    }

    private func resolveMetric(window: ClaudeUsageWindow?, cacheKey: String) -> UsageMetric {
        if let window {
            let metric = UsageMetric(
                used: window.utilization,
                total: 100,
                unit: .percent,
                resetTime: window.resets_at.flatMap { DateUtils.parseISO8601($0) }
            )
            saveMetricCache(metric, forKey: cacheKey)
            return metric
        }

        if let cached = loadMetricCache(forKey: cacheKey) {
            let now = Date()
            if let resetTime = cached.resetTime, resetTime <= now {
                clearMetricCache(forKey: cacheKey)
            } else {
                return cached
            }
        }

        return UsageMetric(used: 0, total: 100, unit: .percent, resetTime: nil)
    }

    private func saveMetricCache(_ metric: UsageMetric, forKey key: String) {
        defaults.set(metric.used, forKey: "\(key).used")
        defaults.set(metric.total, forKey: "\(key).total")
        defaults.set(metric.resetTime?.timeIntervalSince1970, forKey: "\(key).resetTime")
    }

    private func loadMetricCache(forKey key: String) -> UsageMetric? {
        guard defaults.object(forKey: "\(key).used") != nil else { return nil }
        let used = defaults.double(forKey: "\(key).used")
        let total = defaults.object(forKey: "\(key).total") != nil ? defaults.double(forKey: "\(key).total") : 100
        let resetTimestamp = defaults.object(forKey: "\(key).resetTime") as? Double
        let resetTime = resetTimestamp.map { Date(timeIntervalSince1970: $0) }
        return UsageMetric(used: used, total: total, unit: .percent, resetTime: resetTime)
    }

    private func clearMetricCache(forKey key: String) {
        defaults.removeObject(forKey: "\(key).used")
        defaults.removeObject(forKey: "\(key).total")
        defaults.removeObject(forKey: "\(key).resetTime")
    }

    // MARK: - Keychain Access via security CLI

    /// Reads the Claude Code OAuth token using the `security` CLI to avoid
    /// per-app Keychain ACL prompts. The result is cached with a TTL matching
    /// the app's refresh interval.
    static func readKeychainTokenViaCLI(now: Date = Date(), cacheTTL: TimeInterval? = nil) -> String? {
        let effectiveTTL = max(0, cacheTTL ?? cacheTTLFromRefreshInterval())
        tokenCacheLock.lock()
        defer { tokenCacheLock.unlock() }

        if let lastLookup = tokenLastLookupAt,
           now.timeIntervalSince(lastLookup) < effectiveTTL {
            return cachedToken
        }

        let rawJSON = securityCLIRunner(securityCLITimeout)
        let token = rawJSON.flatMap { parseAccessToken(from: $0) }
        cachedToken = token
        tokenLastLookupAt = now
        return token
    }

    static func resetTokenCache() {
        tokenCacheLock.lock()
        cachedToken = nil
        tokenLastLookupAt = nil
        tokenCacheLock.unlock()
    }

    /// Parses the OAuth access token from the raw JSON credential blob.
    static func parseAccessToken(from jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let creds = try? JSONDecoder().decode(ClaudeOAuthCredentials.self, from: data) else {
            return nil
        }
        return creds.claudeAiOauth.accessToken
    }

    private static func cacheTTLFromRefreshInterval() -> TimeInterval {
        let refreshInterval = UserDefaults.standard.double(forKey: "refreshInterval")
        return refreshInterval > 0 ? refreshInterval : defaultCacheTTL
    }

    /// Runs `security find-generic-password -s "Claude Code-credentials" -w`
    /// which outputs the password data to stdout. The `security` binary is a
    /// system-trusted application so it bypasses per-app ACL prompts.
    private static func runSecurityCLICommand(timeout: TimeInterval) -> String? {
        CLIProcessExecutor.executeCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/security"),
            arguments: ["find-generic-password", "-s", keychainService, "-w"],
            timeout: timeout
        )
    }

    static func executeSecurityCLICommand(timeout: TimeInterval, runtime: SecurityCLIProcessRuntime) -> String? {
        CLIProcessExecutor.executeCommand(timeout: timeout, runtime: runtime)
    }
}
