import XCTest
@testable import CCUsageBar

final class CopilotUsageProviderTests: XCTestCase {

    override func setUp() {
        super.setUp()
        CopilotMockURLProtocol.reset()
    }

    override func tearDown() {
        CopilotMockURLProtocol.reset()
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

    func testSendsCorrectHeaders() async throws {
        let json = """
        {"copilot_plan": "free", "quota_snapshots": [{"quota_id": "premium_requests", "entitlement": 50, "remaining": 50, "unlimited": false}]}
        """
        CopilotMockURLProtocol.stubResponse(data: Data(json.utf8), statusCode: 200)
        CopilotMockURLProtocol.onRequest = { request in
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
        config.protocolClasses = [CopilotMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        CopilotMockURLProtocol.onRequest?(request)

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: CopilotMockURLProtocol.stubStatusCode,
            httpVersion: nil,
            headerFields: nil
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: CopilotMockURLProtocol.stubData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
