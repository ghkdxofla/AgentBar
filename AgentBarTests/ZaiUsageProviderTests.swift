import XCTest
@testable import AgentBar

final class ZaiUsageProviderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ZaiMockURLProtocol.reset()
        invalidateProviderCache()
    }

    override func tearDown() {
        ZaiMockURLProtocol.reset()
        invalidateProviderCache()
        super.tearDown()
    }

    func testFetchUsageParsesTokensAndMCPLimits() async throws {
        let json = """
        {
          "code": 0,
          "success": true,
          "data": {
            "level": "pro",
            "limits": [
              {
                "type": "TOKENS_LIMIT",
                "percentage": 42.5,
                "nextResetTime": 1739607600000
              },
              {
                "type": "TIME_LIMIT",
                "usage": 500,
                "currentValue": 123,
                "nextResetTime": 1739700000000
              }
            ]
          }
        }
        """
        ZaiMockURLProtocol.stubResponse(data: Data(json.utf8), statusCode: 200)

        let provider = makeProvider(credential: "zai_test_key")
        let usage = try await provider.fetchUsage()

        XCTAssertEqual(usage.service, .zai)
        XCTAssertTrue(usage.isAvailable)
        XCTAssertEqual(usage.planName, "Pro")

        XCTAssertEqual(usage.fiveHourUsage.unit, .percent)
        XCTAssertEqual(usage.fiveHourUsage.used, 42.5)
        XCTAssertEqual(usage.fiveHourUsage.total, 100)
        XCTAssertEqual(usage.fiveHourUsage.resetTime, Date(timeIntervalSince1970: 1739607600))

        XCTAssertEqual(usage.weeklyUsage?.unit, .requests)
        XCTAssertEqual(usage.weeklyUsage?.used, 123)
        XCTAssertEqual(usage.weeklyUsage?.total, 500)
        XCTAssertEqual(usage.weeklyUsage?.resetTime, Date(timeIntervalSince1970: 1739700000))
    }

    func testFetchUsageRetriesWithRawAuthorizationAfterBearerUnauthorized() async throws {
        let json = """
        {
          "code": 0,
          "success": true,
          "data": {
            "limits": [
              { "type": "TOKENS_LIMIT", "percentage": 10 },
              { "type": "TIME_LIMIT", "usage": 100, "currentValue": 5 }
            ]
          }
        }
        """

        ZaiMockURLProtocol.responseProvider = { request in
            let auth = request.value(forHTTPHeaderField: "Authorization")
            if auth == "Bearer retry_key" {
                return (Data(), 401)
            }
            return (Data(json.utf8), 200)
        }

        let provider = makeProvider(credential: "retry_key")
        let usage = try await provider.fetchUsage()

        XCTAssertEqual(ZaiMockURLProtocol.requestCount, 2)
        XCTAssertEqual(ZaiMockURLProtocol.authorizations, ["Bearer retry_key", "retry_key"])
        XCTAssertEqual(usage.fiveHourUsage.used, 10)
        XCTAssertEqual(usage.weeklyUsage?.used, 5)
    }

    func testFetchUsageThrowsUnauthorizedWhenAPIKeyMissing() async {
        let provider = makeProvider(credential: nil)

        do {
            _ = try await provider.fetchUsage()
            XCTFail("Expected unauthorized error")
        } catch let error as APIError {
            guard case .unauthorized = error else {
                XCTFail("Expected unauthorized, got \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchUsageThrowsNoDataWhenLimitsMissing() async throws {
        let json = """
        {
          "code": 0,
          "success": true,
          "data": {
            "level": "pro"
          }
        }
        """
        ZaiMockURLProtocol.stubResponse(data: Data(json.utf8), statusCode: 200)

        let provider = makeProvider(credential: "zai_test_key")

        do {
            _ = try await provider.fetchUsage()
            XCTFail("Expected noData error")
        } catch let error as APIError {
            guard case .noData = error else {
                XCTFail("Expected noData, got \(error)")
                return
            }
        }
    }

    func testFetchUsageUsesCacheWithinTTL() async throws {
        let cached = UsageData(
            service: .zai,
            fiveHourUsage: UsageMetric(used: 77, total: 100, unit: .percent, resetTime: nil),
            weeklyUsage: UsageMetric(used: 7, total: 50, unit: .requests, resetTime: nil),
            lastUpdated: Date(timeIntervalSince1970: 1234),
            isAvailable: true,
            planName: "Cached"
        )
        ZaiUsageProvider.updateCache(cached, now: Date())

        let provider = makeProvider(credential: "zai_test_key")
        let usage = try await provider.fetchUsage()

        XCTAssertEqual(usage.planName, "Cached")
        XCTAssertEqual(usage.fiveHourUsage.used, 77)
        XCTAssertEqual(ZaiMockURLProtocol.requestCount, 0)
    }

    func testCachedIfFreshReturnsNilWhenExpired() {
        let cached = UsageData(
            service: .zai,
            fiveHourUsage: UsageMetric(used: 1, total: 100, unit: .percent, resetTime: nil),
            weeklyUsage: UsageMetric(used: 1, total: 10, unit: .requests, resetTime: nil),
            lastUpdated: Date(timeIntervalSince1970: 0),
            isAvailable: true,
            planName: nil
        )
        ZaiUsageProvider.updateCache(cached, now: Date(timeIntervalSince1970: 1000))

        let now = Date(timeIntervalSince1970: 1000 + ZaiUsageProvider.minCacheTTL + 1)
        XCTAssertNil(ZaiUsageProvider.cachedIfFresh(now: now))
    }

    func testIsConfiguredReflectsCredentialProvider() async {
        let noCredProvider = makeProvider(credential: nil)
        let noCredConfigured = await noCredProvider.isConfigured()
        XCTAssertFalse(noCredConfigured)

        let withCredProvider = makeProvider(credential: "zai_test_key")
        let withCredConfigured = await withCredProvider.isConfigured()
        XCTAssertTrue(withCredConfigured)
    }

    func testCapitalizedPlanNameCapitalizesFirstLetterOnly() {
        XCTAssertEqual(ZaiUsageProvider.capitalizedPlanName("pro"), "Pro")
        XCTAssertEqual(ZaiUsageProvider.capitalizedPlanName(""), "")
        XCTAssertEqual(ZaiUsageProvider.capitalizedPlanName("MAX"), "MAX")
    }

    private func makeProvider(credential: String? = "zai_test_key") -> ZaiUsageProvider {
        ZaiUsageProvider(
            apiClient: APIClient(session: ZaiMockURLProtocol.session()),
            credentialProvider: { credential }
        )
    }

    private func invalidateProviderCache() {
        let stale = UsageData(
            service: .zai,
            fiveHourUsage: UsageMetric(used: 0, total: 100, unit: .percent, resetTime: nil),
            weeklyUsage: UsageMetric(used: 0, total: 0, unit: .requests, resetTime: nil),
            lastUpdated: Date(timeIntervalSince1970: 0),
            isAvailable: true,
            planName: nil
        )
        ZaiUsageProvider.updateCache(stale, now: Date.distantPast)
    }
}

private final class ZaiMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestCount: Int = 0
    nonisolated(unsafe) static var authorizations: [String] = []
    nonisolated(unsafe) static var stubData: Data = Data()
    nonisolated(unsafe) static var stubStatusCode: Int = 200
    nonisolated(unsafe) static var responseProvider: ((URLRequest) -> (data: Data, statusCode: Int))?

    static func reset() {
        requestCount = 0
        authorizations = []
        stubData = Data()
        stubStatusCode = 200
        responseProvider = nil
    }

    static func stubResponse(data: Data, statusCode: Int) {
        stubData = data
        stubStatusCode = statusCode
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ZaiMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        ZaiMockURLProtocol.requestCount += 1
        ZaiMockURLProtocol.authorizations.append(request.value(forHTTPHeaderField: "Authorization") ?? "")

        let responseData: Data
        let statusCode: Int
        if let provided = ZaiMockURLProtocol.responseProvider?(request) {
            responseData = provided.data
            statusCode = provided.statusCode
        } else {
            responseData = ZaiMockURLProtocol.stubData
            statusCode = ZaiMockURLProtocol.stubStatusCode
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
