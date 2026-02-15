import XCTest
import SQLite3
@testable import CCUsageBar

final class CursorUsageProviderTests: XCTestCase {

    override func setUp() {
        super.setUp()
        CursorMockURLProtocol.reset()
    }

    override func tearDown() {
        CursorMockURLProtocol.reset()
        super.tearDown()
    }

    func testFetchesUsageFromAPI() async throws {
        // Create a temp SQLite DB with a test JWT
        let dbPath = try createTempDB(jwt: makeTestJWT(sub: "user_abc123"))

        let json = """
        {
            "startOfMonth": "2026-02-01T00:00:00.000Z",
            "gpt-4": {"numRequests": 30, "numRequestsTotal": 30, "maxRequestUsage": 500, "numTokens": 50000},
            "gpt-3.5-turbo": {"numRequests": 10, "numRequestsTotal": 10, "maxRequestUsage": null, "numTokens": 20000},
            "cursor-small": {"numRequests": 5, "numRequestsTotal": 5, "maxRequestUsage": null, "numTokens": 10000}
        }
        """
        CursorMockURLProtocol.stubResponse(data: Data(json.utf8), statusCode: 200)

        let provider = CursorUsageProvider(
            monthlyRequestLimit: 500,
            session: CursorMockURLProtocol.session(),
            dbPathProvider: { dbPath }
        )

        let usage = try await provider.fetchUsage()

        XCTAssertEqual(usage.service, .cursor)
        XCTAssertTrue(usage.isAvailable)
        XCTAssertEqual(usage.fiveHourUsage.unit, .requests)
        XCTAssertEqual(usage.fiveHourUsage.used, 45)   // 30 + 10 + 5
        XCTAssertEqual(usage.fiveHourUsage.total, 500)  // from maxRequestUsage
        XCTAssertNil(usage.weeklyUsage)
    }

    func testComputesResetFromStartOfMonth() async throws {
        let dbPath = try createTempDB(jwt: makeTestJWT(sub: "user_xyz"))

        let json = """
        {
            "startOfMonth": "2026-02-01T00:00:00.000Z",
            "gpt-4": {"numRequests": 0, "numRequestsTotal": 0, "maxRequestUsage": 500, "numTokens": 0}
        }
        """
        CursorMockURLProtocol.stubResponse(data: Data(json.utf8), statusCode: 200)

        let provider = CursorUsageProvider(
            session: CursorMockURLProtocol.session(),
            dbPathProvider: { dbPath }
        )

        let usage = try await provider.fetchUsage()

        // Reset should be startOfMonth + 1 month = 2026-03-01
        XCTAssertNotNil(usage.fiveHourUsage.resetTime)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents([.year, .month, .day], from: usage.fiveHourUsage.resetTime!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 1)
    }

    func testHandlesMissingDatabase() async {
        let provider = CursorUsageProvider(
            dbPathProvider: { "/nonexistent/path/state.vscdb" }
        )

        let isConfigured = await provider.isConfigured()
        XCTAssertFalse(isConfigured)
    }

    func testHandlesNullMaxRequestUsage() async throws {
        let dbPath = try createTempDB(jwt: makeTestJWT(sub: "user_test"))

        let json = """
        {
            "startOfMonth": "2026-02-01T00:00:00.000Z",
            "gpt-4": {"numRequests": 100, "numRequestsTotal": 100, "maxRequestUsage": null, "numTokens": 0}
        }
        """
        CursorMockURLProtocol.stubResponse(data: Data(json.utf8), statusCode: 200)

        let provider = CursorUsageProvider(
            monthlyRequestLimit: 500,
            session: CursorMockURLProtocol.session(),
            dbPathProvider: { dbPath }
        )

        let usage = try await provider.fetchUsage()

        // When maxRequestUsage is null, should fall back to plan limit
        XCTAssertEqual(usage.fiveHourUsage.total, 500)
    }

    func testJWTDecoding() throws {
        let jwt = makeTestJWT(sub: "user_12345")
        let userId = try CursorUsageProvider.decodeUserIdFromJWT(jwt)
        XCTAssertEqual(userId, "user_12345")
    }

    // MARK: - Helpers

    private func makeTestJWT(sub: String) -> String {
        // Header: {"alg":"HS256","typ":"JWT"}
        let header = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"

        // Payload with sub claim
        let payloadJSON = "{\"sub\":\"\(sub)\",\"iat\":1700000000}"
        let payloadData = payloadJSON.data(using: .utf8)!
        let payload = payloadData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        // Fake signature
        let signature = "fake_signature"

        return "\(header).\(payload).\(signature)"
    }

    private func createTempDB(jwt: String) throws -> String {
        let tempDir = NSTemporaryDirectory()
        let dbPath = (tempDir as NSString).appendingPathComponent("test_state_\(UUID().uuidString).vscdb")

        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create test DB"])
        }
        defer { sqlite3_close(db) }

        let createSQL = "CREATE TABLE IF NOT EXISTS ItemTable (key TEXT PRIMARY KEY, value TEXT)"
        guard sqlite3_exec(db, createSQL, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create table"])
        }

        let insertSQL = "INSERT OR REPLACE INTO ItemTable (key, value) VALUES ('cursorAuth/accessToken', ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "test", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare insert"])
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (jwt as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw NSError(domain: "test", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to insert"])
        }

        return dbPath
    }
}

// MARK: - Mock URL Protocol

private final class CursorMockURLProtocol: URLProtocol, @unchecked Sendable {
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
        config.protocolClasses = [CursorMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        CursorMockURLProtocol.onRequest?(request)

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: CursorMockURLProtocol.stubStatusCode,
            httpVersion: nil,
            headerFields: nil
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: CursorMockURLProtocol.stubData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
