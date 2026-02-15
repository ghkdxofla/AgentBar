import Foundation
import SQLite3

// MARK: - API Response Models

struct CursorUsageResponse: Decodable, Sendable {
    let startOfMonth: String?
    let modelUsages: [String: CursorModelUsage]

    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let startOfMonthKey = DynamicCodingKey(stringValue: "startOfMonth")!
        startOfMonth = try container.decodeIfPresent(String.self, forKey: startOfMonthKey)

        var decodedModelUsages: [String: CursorModelUsage] = [:]
        for key in container.allKeys where key.stringValue != "startOfMonth" {
            if let usage = try? container.decode(CursorModelUsage.self, forKey: key) {
                decodedModelUsages[key.stringValue] = usage
            }
        }
        modelUsages = decodedModelUsages
    }

    var allModelUsages: [CursorModelUsage] {
        Array(modelUsages.values)
    }
}

struct CursorModelUsage: Decodable, Sendable {
    let numRequests: Int?
    let numRequestsTotal: Int?
    let maxRequestUsage: Int?
    let numTokens: Int?
}

// MARK: - Provider

final class CursorUsageProvider: UsageProviderProtocol, @unchecked Sendable {
    let serviceType: ServiceType = .cursor

    private let session: URLSession
    private let monthlyRequestLimit: Double
    private let dbPathProvider: @Sendable () -> String

    static let apiBaseURL = "https://www.cursor.com/api/usage"
    static let defaultDBPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    }()

    init(
        monthlyRequestLimit: Double = CursorPlan.pro.monthlyRequestEstimate,
        session: URLSession = .shared,
        dbPathProvider: (@Sendable () -> String)? = nil
    ) {
        self.monthlyRequestLimit = monthlyRequestLimit
        self.session = session
        self.dbPathProvider = dbPathProvider ?? { Self.defaultDBPath }
    }

    func isConfigured() async -> Bool {
        FileManager.default.fileExists(atPath: dbPathProvider())
    }

    func fetchUsage() async throws -> UsageData {
        let dbPath = dbPathProvider()

        // 1. Read JWT from SQLite
        let jwt = try readAccessToken(from: dbPath)

        // 2. Decode JWT to extract user ID
        let userId = try decodeUserIdFromJWT(jwt)

        // 3. Call Cursor usage API
        var components = URLComponents(string: Self.apiBaseURL)
        components?.queryItems = [URLQueryItem(name: "user", value: userId)]
        guard let url = components?.url else {
            throw APIError.invalidResponse
        }

        let encodedUserId = Self.percentEncodeCookieComponent(userId)
        let encodedJWT = Self.percentEncodeCookieComponent(jwt)
        let cookie = "\(encodedUserId)%3A%3A\(encodedJWT)"

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("WorkosCursorSessionToken=\(cookie)", forHTTPHeaderField: "Cookie")
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

        let usageResponse = try JSONDecoder().decode(CursorUsageResponse.self, from: data)

        // 4. Sum requests across all model buckets
        let totalRequests = usageResponse.allModelUsages.compactMap(\.numRequests).reduce(0, +)

        // 5. Determine total from maxRequestUsage or plan limit
        let apiLimit = usageResponse.allModelUsages.compactMap(\.maxRequestUsage).max()
        let total = Double(apiLimit ?? Int(monthlyRequestLimit))

        // 6. Compute reset time from startOfMonth + 1 month
        let resetTime: Date?
        if let startStr = usageResponse.startOfMonth {
            resetTime = Self.parseStartOfMonthReset(startStr)
        } else {
            resetTime = CopilotUsageProvider.firstOfNextMonthUTC()
        }

        return UsageData(
            service: .cursor,
            fiveHourUsage: UsageMetric(
                used: Double(totalRequests),
                total: total,
                unit: .requests,
                resetTime: resetTime
            ),
            weeklyUsage: nil,
            lastUpdated: Date(),
            isAvailable: true
        )
    }

    // MARK: - SQLite Token Reading

    func readAccessToken(from dbPath: String) throws -> String {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw APIError.noData
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let query = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'"
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw APIError.noData
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw APIError.noData
        }

        guard let cString = sqlite3_column_text(stmt, 0) else {
            throw APIError.noData
        }

        return String(cString: cString)
    }

    // MARK: - JWT Decoding

    static func decodeUserIdFromJWT(_ jwt: String) throws -> String {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else {
            throw APIError.decodingError("Invalid JWT format")
        }

        let payload = String(parts[1])
        guard let data = base64URLDecode(payload) else {
            throw APIError.decodingError("Failed to decode JWT payload")
        }

        struct JWTPayload: Decodable {
            let sub: String
        }

        let decoded = try JSONDecoder().decode(JWTPayload.self, from: data)
        return decoded.sub
    }

    func decodeUserIdFromJWT(_ jwt: String) throws -> String {
        try Self.decodeUserIdFromJWT(jwt)
    }

    // MARK: - Helpers

    static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Pad to multiple of 4
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }

    static func percentEncodeCookieComponent(_ string: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    static func parseStartOfMonthReset(_ startOfMonth: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let parsed = formatter.date(from: startOfMonth) ?? {
            let noFrac = ISO8601DateFormatter()
            noFrac.formatOptions = [.withInternetDateTime]
            return noFrac.date(from: startOfMonth)
        }()

        guard let startDate = parsed else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(byAdding: .month, value: 1, to: startDate)
    }
}
