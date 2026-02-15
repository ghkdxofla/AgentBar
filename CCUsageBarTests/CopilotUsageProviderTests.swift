import XCTest
@testable import CCUsageBar

final class CopilotUsageProviderTests: XCTestCase {
    private var originalGHCLICommandRunner: (@Sendable (TimeInterval) -> String?)!
    private var originalGHCLICommandConfiguration: GHCLICommandConfiguration!

    override func setUp() {
        super.setUp()
        CopilotMockURLProtocol.reset()
        CopilotUsageProvider.resetGHCLITokenCache()
        originalGHCLICommandRunner = CopilotUsageProvider.ghCLICommandRunner
        originalGHCLICommandConfiguration = CopilotUsageProvider.ghCLICommandConfiguration
    }

    override func tearDown() {
        CopilotMockURLProtocol.reset()
        CopilotUsageProvider.resetGHCLITokenCache()
        CopilotUsageProvider.ghCLICommandRunner = originalGHCLICommandRunner
        CopilotUsageProvider.ghCLICommandConfiguration = originalGHCLICommandConfiguration
        super.tearDown()
    }

    func testFetchesPremiumRequestUsage() async throws {
        let json = """
        {
            "copilot_plan": "pro",
            "quota_snapshots": [
                {
                    "quota_id": "premium_requests",
                    "entitlement": 300,
                    "remaining": 250,
                    "percent_remaining": 83.33,
                    "overage_count": 0,
                    "unlimited": false
                }
            ]
        }
        """
        CopilotMockURLProtocol.stubResponse(data: Data(json.utf8), statusCode: 200)

        let provider = CopilotUsageProvider(
            session: CopilotMockURLProtocol.session(),
            credentialProvider: { "ghp_test_token" }
        )

        let usage = try await provider.fetchUsage()

        XCTAssertEqual(usage.service, .copilot)
        XCTAssertTrue(usage.isAvailable)
        XCTAssertEqual(usage.fiveHourUsage.unit, .requests)
        XCTAssertEqual(usage.fiveHourUsage.used, 50)   // 300 - 250
        XCTAssertEqual(usage.fiveHourUsage.total, 300)
        XCTAssertNil(usage.weeklyUsage)
    }

    func testCalculatesResetToFirstOfNextMonth() async throws {
        let json = """
        {
            "copilot_plan": "pro",
            "quota_snapshots": [
                {"quota_id": "premium_requests", "entitlement": 300, "remaining": 300, "unlimited": false}
            ]
        }
        """
        CopilotMockURLProtocol.stubResponse(data: Data(json.utf8), statusCode: 200)

        let provider = CopilotUsageProvider(
            session: CopilotMockURLProtocol.session(),
            credentialProvider: { "ghp_test" }
        )

        let usage = try await provider.fetchUsage()

        XCTAssertNotNil(usage.fiveHourUsage.resetTime)

        // Reset should be 1st of next month in UTC
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let resetComponents = calendar.dateComponents([.day], from: usage.fiveHourUsage.resetTime!)
        XCTAssertEqual(resetComponents.day, 1)
    }

    func testHandlesUnlimitedQuota() async throws {
        let json = """
        {
            "copilot_plan": "enterprise",
            "quota_snapshots": [
                {"quota_id": "premium_requests", "entitlement": 0, "remaining": 0, "unlimited": true}
            ]
        }
        """
        CopilotMockURLProtocol.stubResponse(data: Data(json.utf8), statusCode: 200)

        let provider = CopilotUsageProvider(
            session: CopilotMockURLProtocol.session(),
            credentialProvider: { "ghp_test" }
        )

        let usage = try await provider.fetchUsage()

        XCTAssertEqual(usage.fiveHourUsage.used, 0)
        XCTAssertEqual(usage.fiveHourUsage.total, 0)
    }

    func testClampsUsedToZeroWhenRemainingExceedsEntitlement() async throws {
        let json = """
        {
            "copilot_plan": "pro",
            "quota_snapshots": [
                {"quota_id": "premium_requests", "entitlement": 100, "remaining": 250, "unlimited": false}
            ]
        }
        """
        CopilotMockURLProtocol.stubResponse(data: Data(json.utf8), statusCode: 200)

        let provider = CopilotUsageProvider(
            session: CopilotMockURLProtocol.session(),
            credentialProvider: { "ghp_test" }
        )

        let usage = try await provider.fetchUsage()

        XCTAssertEqual(usage.fiveHourUsage.used, 0)
        XCTAssertEqual(usage.fiveHourUsage.total, 100)
    }

    func testHandlesMissingCredentials() async {
        let provider = CopilotUsageProvider(
            credentialProvider: { nil }
        )

        let isConfigured = await provider.isConfigured()
        XCTAssertFalse(isConfigured)
    }

    func testHandles401() async throws {
        CopilotMockURLProtocol.stubResponse(data: Data(), statusCode: 401)

        let provider = CopilotUsageProvider(
            session: CopilotMockURLProtocol.session(),
            credentialProvider: { "expired_token" }
        )

        do {
            _ = try await provider.fetchUsage()
            XCTFail("Should have thrown")
        } catch let error as APIError {
            if case .unauthorized = error {} else {
                XCTFail("Expected unauthorized, got \(error)")
            }
        }
    }

    func testFallsBackToManualPATWhenPrimaryTokenUnauthorized() async throws {
        let json = """
        {
            "copilot_plan": "pro",
            "quota_snapshots": [
                {"quota_id": "premium_requests", "entitlement": 300, "remaining": 200, "unlimited": false}
            ]
        }
        """
        CopilotMockURLProtocol.responseProvider = { request in
            let authHeader = request.value(forHTTPHeaderField: "Authorization")
            if authHeader == "Bearer gh_cli_token" {
                return (Data(), 401)
            }
            return (Data(json.utf8), 200)
        }
        CopilotMockURLProtocol.onRequest = { request, attempt in
            let authHeader = request.value(forHTTPHeaderField: "Authorization")
            if attempt == 0 {
                XCTAssertEqual(authHeader, "Bearer gh_cli_token")
            } else if attempt == 1 {
                XCTAssertEqual(authHeader, "Bearer ghp_manual_pat")
            } else {
                XCTFail("Unexpected extra request attempt")
            }
        }

        let provider = CopilotUsageProvider(
            session: CopilotMockURLProtocol.session(),
            credentialProvider: { "gh_cli_token" },
            fallbackCredentialProvider: { "ghp_manual_pat" }
        )

        let usage = try await provider.fetchUsage()

        XCTAssertEqual(CopilotMockURLProtocol.requestCount, 2)
        XCTAssertEqual(usage.fiveHourUsage.used, 100)
        XCTAssertEqual(usage.fiveHourUsage.total, 300)
    }

    func testReadGHCLITokenCachesResultWithinTTL() {
        let counter = CounterBox()
        CopilotUsageProvider.ghCLICommandRunner = { _ in
            counter.increment()
            return "ghp_cached"
        }

        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(CopilotUsageProvider.readGHCLIToken(now: now, cacheTTL: 60), "ghp_cached")
        XCTAssertEqual(CopilotUsageProvider.readGHCLIToken(now: now.addingTimeInterval(10), cacheTTL: 60), "ghp_cached")
        XCTAssertEqual(counter.value, 1)

        XCTAssertEqual(CopilotUsageProvider.readGHCLIToken(now: now.addingTimeInterval(61), cacheTTL: 60), "ghp_cached")
        XCTAssertEqual(counter.value, 2)
    }

    func testReadGHCLITokenCachesTimeoutFailureWithinTTL() {
        let counter = CounterBox()
        CopilotUsageProvider.ghCLICommandRunner = { _ in
            counter.increment()
            return nil
        }

        let now = Date(timeIntervalSince1970: 2_000)
        XCTAssertNil(CopilotUsageProvider.readGHCLIToken(now: now, cacheTTL: 60))
        XCTAssertNil(CopilotUsageProvider.readGHCLIToken(now: now.addingTimeInterval(5), cacheTTL: 60))
        XCTAssertEqual(counter.value, 1)
    }

    func testExecuteGHCLICommandTimeoutTerminatesRunningProcess() {
        var terminateCallCount = 0
        var waitTimeouts: [TimeInterval] = []
        let runtime = CopilotUsageProvider.GHCLIProcessRuntime(
            run: {},
            waitForTermination: { timeout in
                waitTimeouts.append(timeout)
                return .timedOut
            },
            isRunning: { true },
            terminate: { terminateCallCount += 1 },
            terminationStatus: { 0 },
            readOutput: { Data() }
        )

        let result = CopilotUsageProvider.executeGHCLICommand(timeout: 0.05, runtime: runtime)

        XCTAssertNil(result)
        XCTAssertEqual(terminateCallCount, 1)
        XCTAssertEqual(waitTimeouts.count, 2)
        XCTAssertEqual(waitTimeouts[0], 0.05, accuracy: 0.0001)
        XCTAssertEqual(waitTimeouts[1], 0.25, accuracy: 0.0001)
    }

    func testSendsCorrectHeaders() async throws {
        let json = """
        {"copilot_plan": "free", "quota_snapshots": [{"quota_id": "premium_requests", "entitlement": 50, "remaining": 50, "unlimited": false}]}
        """
        CopilotMockURLProtocol.stubResponse(data: Data(json.utf8), statusCode: 200)
        CopilotMockURLProtocol.onRequest = { request, _ in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ghp_my_token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "CCUsageBar")
            XCTAssertEqual(request.url, CopilotUsageProvider.apiURL)
        }

        let provider = CopilotUsageProvider(
            session: CopilotMockURLProtocol.session(),
            credentialProvider: { "ghp_my_token" }
        )

        _ = try await provider.fetchUsage()
    }

}

// MARK: - Mock URL Protocol

private final class CopilotMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var stubData: Data = Data()
    nonisolated(unsafe) static var stubStatusCode: Int = 200
    nonisolated(unsafe) static var requestCount: Int = 0
    nonisolated(unsafe) static var responseProvider: ((URLRequest) -> (data: Data, statusCode: Int))?
    nonisolated(unsafe) static var onRequest: ((URLRequest, Int) -> Void)?

    static func reset() {
        stubData = Data()
        stubStatusCode = 200
        requestCount = 0
        responseProvider = nil
        onRequest = nil
    }

    static func stubResponse(data: Data, statusCode: Int) {
        stubData = data
        stubStatusCode = statusCode
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CopilotMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let currentRequestCount = CopilotMockURLProtocol.requestCount
        CopilotMockURLProtocol.requestCount += 1
        CopilotMockURLProtocol.onRequest?(request, currentRequestCount)

        let stubbed = CopilotMockURLProtocol.responseProvider?(request)
        let data = stubbed?.data ?? CopilotMockURLProtocol.stubData
        let statusCode = stubbed?.statusCode ?? CopilotMockURLProtocol.stubStatusCode

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class CounterBox: @unchecked Sendable {
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
