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

    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private static let keychainService = "Claude Code-credentials"
    private static let tokenCacheLock = NSLock()
    private static let defaultCacheTTL: TimeInterval = 60
    private static let securityCLITimeout: TimeInterval = 2
    nonisolated(unsafe) private static var cachedToken: String?
    nonisolated(unsafe) private static var tokenLastLookupAt: Date?
    nonisolated(unsafe) static var securityCLIRunner: @Sendable (_ timeout: TimeInterval) -> String? = { timeout in
        runSecurityCLICommand(timeout: timeout)
    }

    init(
        session: URLSession = .shared,
        credentialProvider: (@Sendable () -> String?)? = nil
    ) {
        self.session = session
        self.credentialProvider = credentialProvider ?? { Self.readKeychainTokenViaCLI() }
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
        let process = Process()
        let pipe = Pipe()
        let terminationSignal = DispatchSemaphore(value: 0)

        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in
            terminationSignal.signal()
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        let waitResult = terminationSignal.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            if process.isRunning {
                process.terminate()
                _ = terminationSignal.wait(timeout: .now() + 0.25)
            }
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output?.isEmpty == true ? nil : output
    }
}
