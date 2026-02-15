import XCTest
@testable import CCUsageBar

final class ClaudeUsageProviderTests: XCTestCase {
    private var originalSecurityCLIRunner: (@Sendable (TimeInterval) -> String?)!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        ClaudeUsageProvider.resetTokenCache()
        originalSecurityCLIRunner = ClaudeUsageProvider.securityCLIRunner
    }

    override func tearDown() {
        MockURLProtocol.reset()
        ClaudeUsageProvider.resetTokenCache()
        ClaudeUsageProvider.securityCLIRunner = originalSecurityCLIRunner
        super.tearDown()
    }

    func testFetchesUsageFromAPI() async throws {
        let json = """
        {
            "five_hour": {"utilization": 19.0, "resets_at": "2026-02-14T18:00:01.107582+00:00"},
            "seven_day": {"utilization": 50.0, "resets_at": "2026-02-16T09:00:00.107602+00:00"}
        }
        """
        MockURLProtocol.stubResponse(data: Data(json.utf8), statusCode: 200)

        let provider = ClaudeUsageProvider(
            session: MockURLProtocol.session(),
            credentialProvider: { "test-token" }
        )

        let usage = try await provider.fetchUsage()

        XCTAssertEqual(usage.service, .claude)
        XCTAssertTrue(usage.isAvailable)
        XCTAssertEqual(usage.fiveHourUsage.unit, .percent)
        XCTAssertEqual(usage.fiveHourUsage.used, 19.0)
        XCTAssertEqual(usage.fiveHourUsage.total, 100)
        XCTAssertEqual(usage.weeklyUsage?.used, 50.0)
        XCTAssertEqual(usage.weeklyUsage?.total, 100)
    }

    func testParsesResetTimes() async throws {
        let json = """
        {
            "five_hour": {"utilization": 5.0, "resets_at": "2026-02-14T18:00:01.107582+00:00"},
            "seven_day": {"utilization": 10.0, "resets_at": "2026-02-16T09:00:00.107602+00:00"}
        }
        """
        MockURLProtocol.stubResponse(data: Data(json.utf8), statusCode: 200)

        let provider = ClaudeUsageProvider(
            session: MockURLProtocol.session(),
            credentialProvider: { "test-token" }
        )

        let usage = try await provider.fetchUsage()

        XCTAssertNotNil(usage.fiveHourUsage.resetTime)
        XCTAssertNotNil(usage.weeklyUsage?.resetTime)

        // Verify reset time is in the future relative to the test fixture date
        let expectedFiveHour = DateUtils.parseISO8601("2026-02-14T18:00:01.107582+00:00")!
        XCTAssertEqual(
            usage.fiveHourUsage.resetTime!.timeIntervalSince1970,
            expectedFiveHour.timeIntervalSince1970,
            accuracy: 1
        )
    }

    func testPercentageCalculation() async throws {
        let json = """
        {
            "five_hour": {"utilization": 85.0, "resets_at": null},
            "seven_day": {"utilization": 42.0, "resets_at": null}
        }
        """
        MockURLProtocol.stubResponse(data: Data(json.utf8), statusCode: 200)

        let provider = ClaudeUsageProvider(
            session: MockURLProtocol.session(),
            credentialProvider: { "test-token" }
        )

        let usage = try await provider.fetchUsage()

        // percentage = used / total = 85 / 100 = 0.85
        XCTAssertEqual(usage.fiveHourUsage.percentage, 0.85, accuracy: 0.001)
        XCTAssertEqual(usage.weeklyUsage!.percentage, 0.42, accuracy: 0.001)
    }

    func testHandlesNullWindows() async throws {
        let json = """
        {
            "five_hour": null,
            "seven_day": null
        }
        """
        MockURLProtocol.stubResponse(data: Data(json.utf8), statusCode: 200)

        let provider = ClaudeUsageProvider(
            session: MockURLProtocol.session(),
            credentialProvider: { "test-token" }
        )

        let usage = try await provider.fetchUsage()

        XCTAssertEqual(usage.fiveHourUsage.used, 0)
        XCTAssertEqual(usage.weeklyUsage?.used, 0)
        XCTAssertNil(usage.fiveHourUsage.resetTime)
    }

    func testHandlesUnauthorized() async throws {
        MockURLProtocol.stubResponse(data: Data(), statusCode: 401)

        let provider = ClaudeUsageProvider(
            session: MockURLProtocol.session(),
            credentialProvider: { "expired-token" }
        )

        do {
            _ = try await provider.fetchUsage()
            XCTFail("Should have thrown")
        } catch {
            // Expected — unauthorized
        }
    }

    func testHandlesMissingCredentials() async {
        let provider = ClaudeUsageProvider(
            credentialProvider: { nil }
        )

        let isConfigured = await provider.isConfigured()
        XCTAssertFalse(isConfigured)
    }

    func testSendsCorrectHeaders() async throws {
        let json = """
        {"five_hour": {"utilization": 0, "resets_at": null}, "seven_day": null}
        """
        MockURLProtocol.stubResponse(data: Data(json.utf8), statusCode: 200)
        MockURLProtocol.onRequest = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer my-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
            XCTAssertEqual(request.url, ClaudeUsageProvider.usageURL)
        }

        let provider = ClaudeUsageProvider(
            session: MockURLProtocol.session(),
            credentialProvider: { "my-token" }
        )

        _ = try await provider.fetchUsage()
    }

    // MARK: - security CLI token reading

    func testReadKeychainTokenViaCLICachesWithinTTL() {
        let credJSON = """
        {"claudeAiOauth":{"accessToken":"cached-token"}}
        """
        let counter = CLICounterBox()
        ClaudeUsageProvider.securityCLIRunner = { _ in
            counter.increment()
            return credJSON
        }

        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(ClaudeUsageProvider.readKeychainTokenViaCLI(now: now, cacheTTL: 60), "cached-token")
        XCTAssertEqual(ClaudeUsageProvider.readKeychainTokenViaCLI(now: now.addingTimeInterval(10), cacheTTL: 60), "cached-token")
        XCTAssertEqual(counter.value, 1, "Should only call CLI once within TTL")

        // After TTL expires, should call again
        XCTAssertEqual(ClaudeUsageProvider.readKeychainTokenViaCLI(now: now.addingTimeInterval(61), cacheTTL: 60), "cached-token")
        XCTAssertEqual(counter.value, 2)
    }

    func testReadKeychainTokenViaCLICachesNilOnFailure() {
        let counter = CLICounterBox()
        ClaudeUsageProvider.securityCLIRunner = { _ in
            counter.increment()
            return nil
        }

        let now = Date(timeIntervalSince1970: 2_000)
        XCTAssertNil(ClaudeUsageProvider.readKeychainTokenViaCLI(now: now, cacheTTL: 60))
        XCTAssertNil(ClaudeUsageProvider.readKeychainTokenViaCLI(now: now.addingTimeInterval(5), cacheTTL: 60))
        XCTAssertEqual(counter.value, 1)
    }

    func testExecuteSecurityCLICommandTimeoutForceKillsIfStillRunning() {
        var terminateCallCount = 0
        var forceTerminateCallCount = 0
        var waitTimeouts: [TimeInterval] = []
        let runtime = ClaudeUsageProvider.SecurityCLIProcessRuntime(
            run: {},
            waitForTermination: { timeout in
                waitTimeouts.append(timeout)
                return .timedOut
            },
            isRunning: { true },
            terminate: { terminateCallCount += 1 },
            forceTerminate: { forceTerminateCallCount += 1 },
            terminationStatus: { 0 },
            readOutput: { Data() }
        )

        let result = ClaudeUsageProvider.executeSecurityCLICommand(timeout: 0.05, runtime: runtime)

        XCTAssertNil(result)
        XCTAssertEqual(terminateCallCount, 1)
        XCTAssertEqual(forceTerminateCallCount, 1)
        XCTAssertEqual(waitTimeouts.count, 3)
        XCTAssertEqual(waitTimeouts[0], 0.05, accuracy: 0.0001)
        XCTAssertEqual(waitTimeouts[1], 0.25, accuracy: 0.0001)
        XCTAssertEqual(waitTimeouts[2], 0.25, accuracy: 0.0001)
    }

    func testExecuteSecurityCLICommandTimeoutDoesNotForceKillWhenTerminateStopsProcess() {
        var terminateCallCount = 0
        var forceTerminateCallCount = 0
        var waitTimeouts: [TimeInterval] = []
        var isRunningCheckCount = 0
        let runtime = ClaudeUsageProvider.SecurityCLIProcessRuntime(
            run: {},
            waitForTermination: { timeout in
                waitTimeouts.append(timeout)
                return .timedOut
            },
            isRunning: {
                defer { isRunningCheckCount += 1 }
                return isRunningCheckCount == 0
            },
            terminate: { terminateCallCount += 1 },
            forceTerminate: { forceTerminateCallCount += 1 },
            terminationStatus: { 0 },
            readOutput: { Data() }
        )

        let result = ClaudeUsageProvider.executeSecurityCLICommand(timeout: 0.05, runtime: runtime)

        XCTAssertNil(result)
        XCTAssertEqual(terminateCallCount, 1)
        XCTAssertEqual(forceTerminateCallCount, 0)
        XCTAssertEqual(waitTimeouts.count, 2)
        XCTAssertEqual(waitTimeouts[0], 0.05, accuracy: 0.0001)
        XCTAssertEqual(waitTimeouts[1], 0.25, accuracy: 0.0001)
    }

    func testExecuteSecurityCLICommandReturnsNilForNonZeroExitStatus() {
        let runtime = ClaudeUsageProvider.SecurityCLIProcessRuntime(
            run: {},
            waitForTermination: { _ in .success },
            isRunning: { false },
            terminate: {},
            terminationStatus: { 1 },
            readOutput: { Data("token".utf8) }
        )

        let result = ClaudeUsageProvider.executeSecurityCLICommand(timeout: 0.05, runtime: runtime)

        XCTAssertNil(result)
    }

    func testExecuteSecurityCLICommandReturnsNilForEmptyOutput() {
        let runtime = ClaudeUsageProvider.SecurityCLIProcessRuntime(
            run: {},
            waitForTermination: { _ in .success },
            isRunning: { false },
            terminate: {},
            terminationStatus: { 0 },
            readOutput: { Data("   \n\t".utf8) }
        )

        let result = ClaudeUsageProvider.executeSecurityCLICommand(timeout: 0.05, runtime: runtime)

        XCTAssertNil(result)
    }

    func testParseAccessTokenFromValidJSON() {
        let json = """
        {"claudeAiOauth":{"accessToken":"sk-ant-oauth-test-123"}}
        """
        XCTAssertEqual(ClaudeUsageProvider.parseAccessToken(from: json), "sk-ant-oauth-test-123")
    }

    func testParseAccessTokenFromInvalidJSON() {
        XCTAssertNil(ClaudeUsageProvider.parseAccessToken(from: "not json"))
        XCTAssertNil(ClaudeUsageProvider.parseAccessToken(from: "{}"))
        XCTAssertNil(ClaudeUsageProvider.parseAccessToken(from: "{\"other\":\"field\"}"))
    }

    func testIgnoresExtraFields() async throws {
        let json = """
        {
            "five_hour": {"utilization": 19.0, "resets_at": "2026-02-14T18:00:01+00:00"},
            "seven_day": {"utilization": 50.0, "resets_at": "2026-02-16T09:00:00+00:00"},
            "seven_day_opus": null,
            "seven_day_sonnet": {"utilization": 3.0, "resets_at": "2026-02-17T00:00:00+00:00"},
            "iguana_necktie": null,
            "extra_usage": {"is_enabled": true, "monthly_limit": 5000}
        }
        """
        MockURLProtocol.stubResponse(data: Data(json.utf8), statusCode: 200)

        let provider = ClaudeUsageProvider(
            session: MockURLProtocol.session(),
            credentialProvider: { "test-token" }
        )

        let usage = try await provider.fetchUsage()

        // Should decode successfully ignoring unknown keys
        XCTAssertEqual(usage.fiveHourUsage.used, 19.0)
        XCTAssertEqual(usage.weeklyUsage?.used, 50.0)
    }
}

// MARK: - Mock URL Protocol

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var stubData: Data = Data()
    nonisolated(unsafe) static var stubStatusCode: Int = 200
    nonisolated(unsafe) static var onRequest: ((URLRequest) -> Void)?

    static func reset() {
        stubData = Data()
        stubStatusCode = 200
        onRequest = nil
    }

    static func stubResponse(data: Data, statusCode: Int) {
        stubData = data
        stubStatusCode = statusCode
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.onRequest?(request)

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: MockURLProtocol.stubStatusCode,
            httpVersion: nil,
            headerFields: nil
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: MockURLProtocol.stubData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class CLICounterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Int = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func increment() {
        lock.lock()
        storedValue += 1
        lock.unlock()
    }
}
