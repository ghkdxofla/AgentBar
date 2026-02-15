import XCTest
@testable import CCUsageBar

final class CodexAlertEventDetectorTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testDetectsTaskCompletedEvent() async throws {
        let file = try makeSessionFile(named: "rollout-task-complete.jsonl")
        let line = """
        {"timestamp":"2026-02-15T10:00:00Z","type":"event_msg","payload":{"type":"task_complete"}}
        """
        try line.write(to: file, atomically: true, encoding: .utf8)

        let detector = CodexAlertEventDetector(sessionsDir: tempDir)
        let events = await detector.detectEvents(since: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .taskCompleted)
        XCTAssertEqual(events.first?.service, .codex)
    }

    func testDetectsPermissionRequiredEventFromEscalatedFunctionCall() async throws {
        let file = try makeSessionFile(named: "rollout-permission.jsonl")
        let line = #"""
        {"timestamp":"2026-02-15T10:00:00Z","type":"response_item","payload":{"type":"function_call","arguments":"{\"cmd\":\"xcodebuild test\",\"sandbox_permissions\":\"require_escalated\",\"justification\":\"Need elevated build access\"}"}}
        """#
        try line.write(to: file, atomically: true, encoding: .utf8)

        let detector = CodexAlertEventDetector(sessionsDir: tempDir)
        let events = await detector.detectEvents(since: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .permissionRequired)
    }

    func testDetectsDecisionRequiredEventFromAgentMessageQuestion() async throws {
        let file = try makeSessionFile(named: "rollout-decision.jsonl")
        let line = """
        {"timestamp":"2026-02-15T10:00:00Z","type":"event_msg","payload":{"type":"agent_message","message":"Should I proceed with migrating the schema?"}}
        """
        try line.write(to: file, atomically: true, encoding: .utf8)

        let detector = CodexAlertEventDetector(sessionsDir: tempDir)
        let events = await detector.detectEvents(since: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .decisionRequired)
    }

    func testIgnoresEventsAtOrBeforeWatermark() async throws {
        let file = try makeSessionFile(named: "rollout-watermark.jsonl")
        let line = """
        {"timestamp":"2026-02-15T10:00:00Z","type":"event_msg","payload":{"type":"task_complete"}}
        """
        try line.write(to: file, atomically: true, encoding: .utf8)

        guard let watermark = DateUtils.parseISO8601("2026-02-15T10:00:00Z") else {
            XCTFail("Failed to create watermark date")
            return
        }

        let detector = CodexAlertEventDetector(sessionsDir: tempDir)
        let events = await detector.detectEvents(since: watermark)

        XCTAssertTrue(events.isEmpty)
    }

    private func makeSessionFile(named filename: String) throws -> URL {
        let dateDir = tempDir.appendingPathComponent("2026/02/15")
        try FileManager.default.createDirectory(at: dateDir, withIntermediateDirectories: true)
        return dateDir.appendingPathComponent(filename)
    }
}

