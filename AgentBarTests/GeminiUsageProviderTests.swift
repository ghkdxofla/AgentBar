import XCTest
@testable import AgentBar

final class GeminiUsageProviderTests: XCTestCase {
    private var tempDir: URL!
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        suiteName = "GeminiUsageProviderTests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testCountsPromptRequestsExcludingCommands() async throws {
        let now = Date(timeIntervalSince1970: 1_770_000_000) // 2026-01-15T08:00:00Z
        try writeLogs([
            #"{"sessionId":"s","messageId":0,"type":"user","message":"Build me a parser","timestamp":"\#(iso8601(now.addingTimeInterval(-30)))"}"#,
            #"{"sessionId":"s","messageId":1,"type":"user","message":"/about","timestamp":"\#(iso8601(now.addingTimeInterval(-20)))"}"#,
            #"{"sessionId":"s","messageId":2,"type":"user","message":"exit","timestamp":"\#(iso8601(now.addingTimeInterval(-10)))"}"#,
            #"{"sessionId":"s","messageId":3,"type":"assistant","message":"response","timestamp":"\#(iso8601(now.addingTimeInterval(-5)))"}"#,
            #"{"sessionId":"s","messageId":4,"type":"user","message":"Summarize this file","timestamp":"\#(iso8601(now.addingTimeInterval(-2 * 3600)))"}"#,
            #"{"sessionId":"s","messageId":5,"type":"user","message":"Old request","timestamp":"\#(iso8601(now.addingTimeInterval(-30 * 3600)))"}"#
        ])

        let provider = GeminiUsageProvider(
            logsRootDir: tempDir,
            dailyRequestLimit: 1_000,
            nowProvider: { now },
            defaults: testDefaults
        )

        let usage = try await provider.fetchUsage()

        XCTAssertEqual(usage.service, .gemini)
        XCTAssertEqual(usage.fiveHourUsage.unit, .requests)
        // Daily window: "Build me a parser" (-30s) + "Summarize this file" (-2h) = 2
        // "Old request" (-30h) is outside the Pacific day
        XCTAssertEqual(usage.fiveHourUsage.used, 2)
        XCTAssertNil(usage.weeklyUsage)
    }

    func testComputesResetTimes() async throws {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        try writeLogs([
            #"{"sessionId":"s","messageId":0,"type":"user","message":"Hello Gemini","timestamp":"\#(iso8601(now.addingTimeInterval(-15)))"}"#
        ])

        let provider = GeminiUsageProvider(
            logsRootDir: tempDir,
            dailyRequestLimit: 1_000,
            nowProvider: { now },
            defaults: testDefaults
        )

        let usage = try await provider.fetchUsage()

        var pacificCalendar = Calendar(identifier: .gregorian)
        pacificCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        let dayStart = pacificCalendar.startOfDay(for: now)
        let expectedDayReset = pacificCalendar.date(byAdding: .day, value: 1, to: dayStart)

        XCTAssertNotNil(usage.fiveHourUsage.resetTime)
        XCTAssertNotNil(expectedDayReset)

        XCTAssertEqual(
            usage.fiveHourUsage.resetTime!.timeIntervalSince1970,
            expectedDayReset!.timeIntervalSince1970,
            accuracy: 1
        )
    }

    func testHandlesMissingDirectory() async {
        let provider = GeminiUsageProvider(
            logsRootDir: URL(fileURLWithPath: "/nonexistent/path"),
            defaults: testDefaults
        )
        let configured = await provider.isConfigured()
        XCTAssertFalse(configured)
    }

    func testCountsPromptsFromNewSessionFormat() async throws {
        let now = Date(timeIntervalSince1970: 1_770_000_000) // 2026-01-15T08:00:00Z
        let sessionJSON = """
        {
          "sessionId": "abc123",
          "messages": [
            {
              "id": "m1",
              "timestamp": "\(iso8601(now.addingTimeInterval(-30)))",
              "type": "user",
              "content": [{"text": "Build me a parser"}]
            },
            {
              "id": "m2",
              "timestamp": "\(iso8601(now.addingTimeInterval(-20)))",
              "type": "user",
              "content": [{"text": "/about"}]
            },
            {
              "id": "m3",
              "timestamp": "\(iso8601(now.addingTimeInterval(-10)))",
              "type": "user",
              "content": [{"text": "exit"}]
            },
            {
              "id": "m4",
              "timestamp": "\(iso8601(now.addingTimeInterval(-5)))",
              "type": "assistant",
              "content": [{"text": "Here is a parser..."}]
            },
            {
              "id": "m5",
              "timestamp": "\(iso8601(now.addingTimeInterval(-2 * 3600)))",
              "type": "user",
              "content": [{"text": "Summarize this file"}]
            },
            {
              "id": "m6",
              "timestamp": "\(iso8601(now.addingTimeInterval(-30 * 3600)))",
              "type": "user",
              "content": [{"text": "Old request"}]
            }
          ]
        }
        """
        try writeSessionFile(sessionJSON)

        let provider = GeminiUsageProvider(
            logsRootDir: tempDir,
            dailyRequestLimit: 1_000,
            nowProvider: { now },
            defaults: testDefaults
        )

        let usage = try await provider.fetchUsage()

        XCTAssertEqual(usage.service, .gemini)
        XCTAssertEqual(usage.fiveHourUsage.unit, .requests)
        // Daily window: "Build me a parser" (-30s) + "Summarize this file" (-2h) = 2
        // "/about" (command), "exit" (quit), assistant message, and "Old request" (-30h outside day) excluded
        XCTAssertEqual(usage.fiveHourUsage.used, 2)
        XCTAssertNil(usage.weeklyUsage)
    }

    func testCountsPromptsFromMixedFormats() async throws {
        let now = Date(timeIntervalSince1970: 1_770_000_000) // 2026-01-15T08:00:00Z

        // Write a logs.json with one countable prompt
        try writeLogs([
            #"{"sessionId":"s","messageId":0,"type":"user","message":"Hello from logs","timestamp":"\#(iso8601(now.addingTimeInterval(-60)))"}"#
        ])

        // Write a session-*.json with two countable prompts
        let sessionJSON = """
        {
          "sessionId": "xyz789",
          "messages": [
            {
              "id": "m1",
              "timestamp": "\(iso8601(now.addingTimeInterval(-45)))",
              "type": "user",
              "content": [{"text": "Hello from session"}]
            },
            {
              "id": "m2",
              "timestamp": "\(iso8601(now.addingTimeInterval(-15)))",
              "type": "user",
              "content": "Plain string content"
            }
          ]
        }
        """
        try writeSessionFile(sessionJSON)

        let provider = GeminiUsageProvider(
            logsRootDir: tempDir,
            dailyRequestLimit: 1_000,
            nowProvider: { now },
            defaults: testDefaults
        )

        let usage = try await provider.fetchUsage()

        XCTAssertEqual(usage.service, .gemini)
        // 1 from logs.json + 2 from session file = 3
        XCTAssertEqual(usage.fiveHourUsage.used, 3)
    }

    // MARK: - Helpers

    private func writeLogs(_ records: [String]) throws {
        let runDir = tempDir.appendingPathComponent("run-1")
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)

        let file = runDir.appendingPathComponent("logs.json")
        let content = "[\n\(records.joined(separator: ",\n"))\n]"
        try content.write(to: file, atomically: true, encoding: .utf8)
    }

    private func writeSessionFile(_ sessionJSON: String, name: String = "session-2026-01-15T08-00-abcd1234.json") throws {
        let chatsDir = tempDir.appendingPathComponent("project-1/chats")
        try FileManager.default.createDirectory(at: chatsDir, withIntermediateDirectories: true)
        let file = chatsDir.appendingPathComponent(name)
        try sessionJSON.write(to: file, atomically: true, encoding: .utf8)
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
