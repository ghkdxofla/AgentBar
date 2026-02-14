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
        {"type":"assistant","timestamp":"\(now)","message":{"id":"msg_1","usage":{"input_tokens":1000,"output_tokens":500}}}
        {"type":"assistant","timestamp":"\(now)","message":{"id":"msg_2","usage":{"input_tokens":2000,"output_tokens":800}}}
        """
        try content.write(to: sessionFile, atomically: true, encoding: .utf8)

        let provider = ClaudeUsageProvider(projectsDir: tempDir)
        let usage = try await provider.fetchUsage()

        XCTAssertEqual(usage.service, .claude)
        XCTAssertTrue(usage.isAvailable)
        // rateLimitTokens: (1000+500) + (2000+800) = 4300
        XCTAssertEqual(usage.fiveHourUsage.used, 4300)
    }

    func testExcludesCacheReadTokens() async throws {
        let projectDir = tempDir.appendingPathComponent("test-project")
        let sessionFile = projectDir.appendingPathComponent("session1.jsonl")
        let now = ISO8601DateFormatter().string(from: Date())
        let content = """
        {"type":"assistant","timestamp":"\(now)","message":{"id":"msg_1","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":50000,"cache_creation_input_tokens":3000}}}
        """
        try content.write(to: sessionFile, atomically: true, encoding: .utf8)

        let provider = ClaudeUsageProvider(projectsDir: tempDir)
        let usage = try await provider.fetchUsage()

        // input_tokens + output_tokens + cache_creation = 100+50+3000 = 3150 (cache_read excluded)
        XCTAssertEqual(usage.fiveHourUsage.used, 3150)
    }

    func testDeduplicatesStreamingRecords() async throws {
        let projectDir = tempDir.appendingPathComponent("test-project")
        let sessionFile = projectDir.appendingPathComponent("session1.jsonl")
        let now = ISO8601DateFormatter().string(from: Date())
        // Same message ID appears 3 times (streaming updates) — only last should count
        let content = """
        {"type":"assistant","timestamp":"\(now)","message":{"id":"msg_1","usage":{"input_tokens":10,"output_tokens":5}}}
        {"type":"assistant","timestamp":"\(now)","message":{"id":"msg_1","usage":{"input_tokens":100,"output_tokens":50}}}
        {"type":"assistant","timestamp":"\(now)","message":{"id":"msg_1","usage":{"input_tokens":1000,"output_tokens":500}}}
        """
        try content.write(to: sessionFile, atomically: true, encoding: .utf8)

        let provider = ClaudeUsageProvider(projectsDir: tempDir)
        let usage = try await provider.fetchUsage()

        // Only last record counts: 1000 + 500 = 1500
        XCTAssertEqual(usage.fiveHourUsage.used, 1500)
    }

    func testIgnoresOldFiles() async throws {
        let projectDir = tempDir.appendingPathComponent("test-project")
        let oldFile = projectDir.appendingPathComponent("old_session.jsonl")
        let oldDate = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-8 * 24 * 3600))
        try """
        {"type":"assistant","timestamp":"\(oldDate)","message":{"id":"msg_1","usage":{"input_tokens":5000,"output_tokens":1000}}}
        """.write(to: oldFile, atomically: true, encoding: .utf8)

        // Set modification date to 8 days ago
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
        // tempDir has a subdirectory but no jsonl files
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
        {"type":"assistant","timestamp":"\(now)","message":{"id":"msg_1","usage":{"input_tokens":100,"output_tokens":50}}}
        """
        try content.write(to: sessionFile, atomically: true, encoding: .utf8)

        let provider = ClaudeUsageProvider(projectsDir: tempDir)
        let usage = try await provider.fetchUsage()

        // Only the assistant record: 100 + 50 = 150
        XCTAssertEqual(usage.fiveHourUsage.used, 150)
    }
}
