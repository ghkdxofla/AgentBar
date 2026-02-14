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
        // No model field → defaults to Opus pricing
        let content = """
        {"type":"assistant","timestamp":"\(now)","model":"claude-opus-4-6","message":{"id":"msg_1","usage":{"input_tokens":1000,"output_tokens":500}}}
        {"type":"assistant","timestamp":"\(now)","model":"claude-opus-4-6","message":{"id":"msg_2","usage":{"input_tokens":2000,"output_tokens":800}}}
        """
        try content.write(to: sessionFile, atomically: true, encoding: .utf8)

        let provider = ClaudeUsageProvider(projectsDir: tempDir)
        let usage = try await provider.fetchUsage()

        XCTAssertEqual(usage.service, .claude)
        XCTAssertTrue(usage.isAvailable)
        XCTAssertEqual(usage.fiveHourUsage.unit, .dollars)
        // Opus: input=$15/M, output=$75/M
        // msg_1: 1000*15/1M + 500*75/1M = 0.015 + 0.0375 = 0.0525
        // msg_2: 2000*15/1M + 800*75/1M = 0.030 + 0.060 = 0.090
        // Total: 0.1425
        XCTAssertEqual(usage.fiveHourUsage.used, 0.1425, accuracy: 0.001)
    }

    func testCostIncludesAllTokenTypes() async throws {
        let projectDir = tempDir.appendingPathComponent("test-project")
        let sessionFile = projectDir.appendingPathComponent("session1.jsonl")
        let now = ISO8601DateFormatter().string(from: Date())
        let content = """
        {"type":"assistant","timestamp":"\(now)","model":"claude-opus-4-6","message":{"id":"msg_1","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":50000,"cache_creation_input_tokens":3000}}}
        """
        try content.write(to: sessionFile, atomically: true, encoding: .utf8)

        let provider = ClaudeUsageProvider(projectsDir: tempDir)
        let usage = try await provider.fetchUsage()

        // Opus pricing: input=$15/M, output=$75/M, cache_creation=$18.75/M, cache_read=$1.50/M
        // 100*15/1M + 50*75/1M + 3000*18.75/1M + 50000*1.50/1M
        // = 0.0015 + 0.00375 + 0.05625 + 0.075 = 0.1365
        XCTAssertEqual(usage.fiveHourUsage.used, 0.1365, accuracy: 0.001)
    }

    func testModelSpecificPricing() async throws {
        let projectDir = tempDir.appendingPathComponent("test-project")
        let sessionFile = projectDir.appendingPathComponent("session1.jsonl")
        let now = ISO8601DateFormatter().string(from: Date())
        let content = """
        {"type":"assistant","timestamp":"\(now)","model":"claude-sonnet-4-5-20250929","message":{"id":"msg_1","usage":{"input_tokens":1000,"output_tokens":1000}}}
        """
        try content.write(to: sessionFile, atomically: true, encoding: .utf8)

        let provider = ClaudeUsageProvider(projectsDir: tempDir)
        let usage = try await provider.fetchUsage()

        // Sonnet: input=$3/M, output=$15/M
        // 1000*3/1M + 1000*15/1M = 0.003 + 0.015 = 0.018
        XCTAssertEqual(usage.fiveHourUsage.used, 0.018, accuracy: 0.001)
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

        // Only last record: 1000*15/1M + 500*75/1M = 0.015 + 0.0375 = 0.0525
        XCTAssertEqual(usage.fiveHourUsage.used, 0.0525, accuracy: 0.001)
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

        // Opus: 100*15/1M + 50*75/1M = 0.0015 + 0.00375 = 0.00525
        XCTAssertEqual(usage.fiveHourUsage.used, 0.00525, accuracy: 0.0001)
    }
}
