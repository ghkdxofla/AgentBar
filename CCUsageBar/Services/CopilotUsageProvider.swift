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

struct GHCLICommandConfiguration: Sendable, Equatable {
    let executableURL: URL
    let arguments: [String]

    static let `default` = GHCLICommandConfiguration(
        executableURL: URL(fileURLWithPath: "/usr/bin/env"),
        arguments: ["gh", "auth", "token"]
    )
}

// MARK: - Provider

final class CopilotUsageProvider: UsageProviderProtocol, @unchecked Sendable {
    let serviceType: ServiceType = .copilot

    private let session: URLSession
    private let primaryCredentialProvider: @Sendable () -> String?
    private let fallbackCredentialProvider: @Sendable () -> String?

    static let apiURL = URL(string: "https://api.github.com/copilot_internal/user")!
    private static let defaultGHTokenCacheTTL: TimeInterval = 60
    private static let ghTokenLookupTimeout: TimeInterval = 2
    private static let ghTokenCacheLock = NSLock()
    nonisolated(unsafe) static var ghCLICommandConfiguration = GHCLICommandConfiguration.default
    nonisolated(unsafe) static var ghCLICommandRunner: @Sendable (_ timeout: TimeInterval) -> String? = { timeout in
        runGHCLICommand(timeout: timeout)
    }
    nonisolated(unsafe) private static var cachedGHCLIToken: String?
    nonisolated(unsafe) private static var ghTokenLastLookupAt: Date?

    struct GHCLIProcessRuntime {
        let run: () throws -> Void
        let waitForTermination: (TimeInterval) -> DispatchTimeoutResult
        let isRunning: () -> Bool
        let terminate: () -> Void
        let terminationStatus: () -> Int32
        let readOutput: () -> Data
    }

    init(
        session: URLSession = .shared,
        credentialProvider: (@Sendable () -> String?)? = nil,
        fallbackCredentialProvider: (@Sendable () -> String?)? = nil
    ) {
        self.session = session
        if let credentialProvider {
            self.primaryCredentialProvider = credentialProvider
            self.fallbackCredentialProvider = fallbackCredentialProvider ?? { nil }
        } else {
            self.primaryCredentialProvider = { Self.readGHCLIToken() }
            self.fallbackCredentialProvider = fallbackCredentialProvider ?? {
                KeychainManager.load(account: ServiceType.copilot.keychainAccount)
            }
        }
    }

    func isConfigured() async -> Bool {
        primaryCredentialProvider() != nil || fallbackCredentialProvider() != nil
    }

    func fetchUsage() async throws -> UsageData {
        if let primaryToken = primaryCredentialProvider() {
            do {
                return try await fetchUsage(using: primaryToken)
            } catch APIError.unauthorized {
                if let fallbackToken = fallbackCredentialProvider(), fallbackToken != primaryToken {
                    return try await fetchUsage(using: fallbackToken)
                }
                throw APIError.unauthorized
            }
        }

        guard let fallbackToken = fallbackCredentialProvider() else {
            throw APIError.unauthorized
        }

        return try await fetchUsage(using: fallbackToken)
    }

    private func fetchUsage(using pat: String) async throws -> UsageData {
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
                let rawUsed = entitlement - remaining
                used = max(0, min(entitlement, rawUsed))
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

    // MARK: - gh CLI Token

    static func readGHCLIToken(now: Date = Date(), cacheTTL: TimeInterval? = nil) -> String? {
        let effectiveCacheTTL = max(0, cacheTTL ?? cacheTTLFromRefreshInterval())
        ghTokenCacheLock.lock()
        defer { ghTokenCacheLock.unlock() }

        if let lastLookupAt = ghTokenLastLookupAt,
           now.timeIntervalSince(lastLookupAt) < effectiveCacheTTL {
            return cachedGHCLIToken
        }

        let token = ghCLICommandRunner(ghTokenLookupTimeout)
        cachedGHCLIToken = token
        ghTokenLastLookupAt = now
        return token
    }

    static func resetGHCLITokenCache() {
        ghTokenCacheLock.lock()
        cachedGHCLIToken = nil
        ghTokenLastLookupAt = nil
        ghTokenCacheLock.unlock()
    }

    private static func cacheTTLFromRefreshInterval() -> TimeInterval {
        let refreshInterval = UserDefaults.standard.double(forKey: "refreshInterval")
        return refreshInterval > 0 ? refreshInterval : defaultGHTokenCacheTTL
    }

    private static func runGHCLICommand(timeout: TimeInterval) -> String? {
        let process = Process()
        let pipe = Pipe()
        let terminationSignal = DispatchSemaphore(value: 0)
        let commandConfiguration = ghCLICommandConfiguration

        process.executableURL = commandConfiguration.executableURL
        process.arguments = commandConfiguration.arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in
            terminationSignal.signal()
        }

        let runtime = GHCLIProcessRuntime(
            run: { try process.run() },
            waitForTermination: { waitTimeout in
                terminationSignal.wait(timeout: .now() + waitTimeout)
            },
            isRunning: { process.isRunning },
            terminate: { process.terminate() },
            terminationStatus: { process.terminationStatus },
            readOutput: { pipe.fileHandleForReading.readDataToEndOfFile() }
        )
        return executeGHCLICommand(timeout: timeout, runtime: runtime)
    }

    static func executeGHCLICommand(timeout: TimeInterval, runtime: GHCLIProcessRuntime) -> String? {
        do {
            try runtime.run()
        } catch {
            return nil
        }

        let waitResult = runtime.waitForTermination(timeout)
        if waitResult == .timedOut {
            if runtime.isRunning() {
                runtime.terminate()
                _ = runtime.waitForTermination(0.25)
            }
            return nil
        }

        guard runtime.terminationStatus() == 0 else { return nil }

        let token = String(data: runtime.readOutput(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return token?.isEmpty == true ? nil : token
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
