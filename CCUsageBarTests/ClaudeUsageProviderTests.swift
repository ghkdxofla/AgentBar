import XCTest
@testable import CCUsageBar

final class ClaudeUsageProviderTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        // Create a subdirectory to mimic a project folder
        let projectDir = tempDir.appendingPathComponent("test-project")
        try! FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testParsesRecentSessionFiles() async throws {
        let projectDir = tempDir.appendingPathComponent("test-project")
        let sessionFile = projectDir.appendingPathComponent("session1.jsonl")
        let now = ISO8601DateFormatter().string(from: Date())
        let content = """
        {"type":"assistant","timestamp":"\(now)","model":"claude-opus-4-6","message":{"id":"msg_1","usage":{"input_tokens":1000,"output_tokens":500}}}
        {"type":"assistant","timestamp":"\(now)","model":"claude-opus-4-6","message":{"id":"msg_2","usage":{"input_tokens":2000,"output_tokens":800}}}
        """
        try content.write(to: sessionFile, atomically: true, encoding: .utf8)

        let provider = ClaudeUsageProvider(projectsDir: tempDir)
        let usage = try await provider.fetchUsage()

        XCTAssertEqual(usage.service, .claude)
        XCTAssertTrue(usage.isAvailable)
        XCTAssertEqual(usage.fiveHourUsage.unit, .tokens)
        // msg_1: 1000 + 500 = 1500
        // msg_2: 2000 + 800 = 2800
        // Total: 4300
        XCTAssertEqual(usage.fiveHourUsage.used, 4300)
    }

    func testSumsAllTokenTypes() async throws {
        let projectDir = tempDir.appendingPathComponent("test-project")
        let sessionFile = projectDir.appendingPathComponent("session1.jsonl")
        let now = ISO8601DateFormatter().string(from: Date())
        let content = """
        {"type":"assistant","timestamp":"\(now)","model":"claude-opus-4-6","message":{"id":"msg_1","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":50000,"cache_creation_input_tokens":3000}}}
        """
        try content.write(to: sessionFile, atomically: true, encoding: .utf8)

        let provider = ClaudeUsageProvider(projectsDir: tempDir)
        let usage = try await provider.fetchUsage()

        // All 4 types: 100 + 50 + 50000 + 3000 = 53150
        XCTAssertEqual(usage.fiveHourUsage.used, 53150)
    }

    func testDeduplicatesStreamingRecords() async throws {
        let projectDir = tempDir.appendingPathComponent("test-project")
        let sessionFile = projectDir.appendingPathComponent("session1.jsonl")
        let now = ISO8601DateFormatter().string(from: Date())
        // Same message ID appears 3 times (streaming updates) — only last should count
        let content = """
        {"type":"assistant","timestamp":"\(now)","model":"claude-opus-4-6","message":{"id":"msg_1","usage":{"input_tokens":10,"output_tokens":5}}}
        {"type":"assistant","timestamp":"\(now)","model":"claude-opus-4-6","message":{"id":"msg_1","usage":{"input_tokens":100,"output_tokens":50}}}
        {"type":"assistant","timestamp":"\(now)","model":"claude-opus-4-6","message":{"id":"msg_1","usage":{"input_tokens":1000,"output_tokens":500}}}
        """
        try content.write(to: sessionFile, atomically: true, encoding: .utf8)

        let provider = ClaudeUsageProvider(projectsDir: tempDir)
        let usage = try await provider.fetchUsage()

        // Only last record: 1000 + 500 = 1500
        XCTAssertEqual(usage.fiveHourUsage.used, 1500)
    }

    func testIgnoresOldFiles() async throws {
        let projectDir = tempDir.appendingPathComponent("test-project")
        let oldFile = projectDir.appendingPathComponent("old_session.jsonl")
        let oldDate = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-8 * 24 * 3600))
        try """
        {"type":"assistant","timestamp":"\(oldDate)","model":"claude-opus-4-6","message":{"id":"msg_1","usage":{"input_tokens":5000,"output_tokens":1000}}}
        """.write(to: oldFile, atomically: true, encoding: .utf8)

        let eightDaysAgo = Date().addingTimeInterval(-8 * 24 * 3600)
        try FileManager.default.setAttributes(
            [.modificationDate: eightDaysAgo],
            ofItemAtPath: oldFile.path
        )

        let provider = ClaudeUsageProvider(projectsDir: tempDir)
        let usage = try await provider.fetchUsage()

        XCTAssertEqual(usage.fiveHourUsage.used, 0)
        XCTAssertEqual(usage.weeklyUsage?.used, 0)
    }

    func testHandlesMissingDirectory() async {
        let provider = ClaudeUsageProvider(
            projectsDir: URL(fileURLWithPath: "/nonexistent/path")
        )
        let isConfigured = await provider.isConfigured()
        XCTAssertFalse(isConfigured)
    }

    func testHandlesEmptyDirectory() async throws {
        let provider = ClaudeUsageProvider(projectsDir: tempDir)
        let usage = try await provider.fetchUsage()

        XCTAssertEqual(usage.fiveHourUsage.used, 0)
        XCTAssertTrue(usage.isAvailable)
    }

    func testIgnoresNonAssistantRecords() async throws {
        let projectDir = tempDir.appendingPathComponent("test-project")
        let sessionFile = projectDir.appendingPathComponent("session1.jsonl")
        let now = ISO8601DateFormatter().string(from: Date())
        let content = """
        {"type":"user","timestamp":"\(now)","message":{"role":"user","content":"hello"}}
        {"type":"file-history-snapshot"}
        {"type":"assistant","timestamp":"\(now)","model":"claude-opus-4-6","message":{"id":"msg_1","usage":{"input_tokens":100,"output_tokens":50}}}
        """
        try content.write(to: sessionFile, atomically: true, encoding: .utf8)

        let provider = ClaudeUsageProvider(projectsDir: tempDir)
        let usage = try await provider.fetchUsage()

        // Only assistant record: 100 + 50 = 150
        XCTAssertEqual(usage.fiveHourUsage.used, 150)
    }

    func testUsesSessionStartForFiveHourReset() async throws {
        let fixedNow = DateUtils.parseISO8601("2026-02-14T12:54:00Z")!
        let projectDir = tempDir.appendingPathComponent("test-project")
        let sessionFile = projectDir.appendingPathComponent("session1.jsonl")
        let userStartTs = "2026-02-14T03:03:35.530Z"
        let assistantTs = "2026-02-14T08:54:13.000Z"
        try """
        {"type":"user","sessionId":"session_1","timestamp":"\(userStartTs)","message":{"role":"user","content":"hello"}}
        {"type":"assistant","sessionId":"session_1","timestamp":"\(assistantTs)","model":"claude-opus-4-6","message":{"id":"msg_session","usage":{"input_tokens":100,"output_tokens":50}}}
        """.write(to: sessionFile, atomically: true, encoding: .utf8)

        let provider = ClaudeUsageProvider(
            projectsDir: tempDir,
            nowProvider: { fixedNow }
        )
        let usage = try await provider.fetchUsage()
        let expected = DateUtils.parseISO8601("2026-02-14T13:03:35.530Z")!

        XCTAssertNotNil(usage.fiveHourUsage.resetTime)
        XCTAssertEqual(
            usage.fiveHourUsage.resetTime!.timeIntervalSince1970,
            expected.timeIntervalSince1970,
            accuracy: 0.001
        )
    }
}
