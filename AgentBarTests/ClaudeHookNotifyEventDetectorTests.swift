import XCTest
@testable import AgentBar

final class ClaudeHookNotifyEventDetectorTests: XCTestCase {
    private var tempDir: URL!
    private var hookFile: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        hookFile = tempDir.appendingPathComponent("hook-events.jsonl")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testDetectsTaskCompletedFromStopHook() async throws {
        let line = try makeBridgeLine(
            capturedAt: "2026-02-15T10:00:00Z",
            payload: HookPayload(
                hookEventName: "Stop",
                sessionID: "session-1",
                message: "Task finished."
            )
        )
        try line.write(to: hookFile, atomically: true, encoding: .utf8)

        let detector = ClaudeHookNotifyEventDetector(hookEventsFile: hookFile)
        let events = await detector.detectEvents(since: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.service, .claude)
        XCTAssertEqual(events.first?.type, .taskCompleted)
        XCTAssertEqual(events.first?.sessionID, "session-1")
    }

    func testDetectsPermissionRequiredFromNotificationMessage() async throws {
        let line = try makeBridgeLine(
            capturedAt: "2026-02-15T10:00:00Z",
            payload: HookPayload(
                hookEventName: "Notification",
                sessionID: "session-2",
                message: "Claude needs your permission to run an elevated Bash command."
            )
        )
        try line.write(to: hookFile, atomically: true, encoding: .utf8)

        let detector = ClaudeHookNotifyEventDetector(hookEventsFile: hookFile)
        let events = await detector.detectEvents(since: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .permissionRequired)
    }

    func testDetectsDecisionRequiredFromNotificationMessage() async throws {
        let line = try makeBridgeLine(
            capturedAt: "2026-02-15T10:00:00Z",
            payload: HookPayload(
                hookEventName: "Notification",
                sessionID: "session-3",
                message: "Claude is waiting for your input before continuing."
            )
        )
        try line.write(to: hookFile, atomically: true, encoding: .utf8)

        let detector = ClaudeHookNotifyEventDetector(hookEventsFile: hookFile)
        let events = await detector.detectEvents(since: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .decisionRequired)
    }

    func testRespectsBoundaryFiltering() async throws {
        let line = try makeBridgeLine(
            capturedAt: "2026-02-15T10:00:00Z",
            payload: HookPayload(
                hookEventName: "Stop",
                sessionID: "session-4",
                message: "Done."
            )
        )
        try line.write(to: hookFile, atomically: true, encoding: .utf8)

        guard let watermark = DateUtils.parseISO8601("2026-02-15T10:00:00Z") else {
            XCTFail("Failed to parse watermark timestamp")
            return
        }

        let detector = ClaudeHookNotifyEventDetector(hookEventsFile: hookFile)
        let exclusive = await detector.detectEvents(since: watermark)
        let inclusive = await detector.detectEvents(since: watermark, includeBoundary: true)

        XCTAssertTrue(exclusive.isEmpty)
        XCTAssertEqual(inclusive.count, 1)
    }

    private func makeBridgeLine(
        capturedAt: String,
        payload: HookPayload
    ) throws -> String {
        let payloadData = try JSONEncoder().encode(payload)
        let envelope = HookEnvelope(
            capturedAt: capturedAt,
            payloadBase64: payloadData.base64EncodedString()
        )
        let data = try JSONEncoder().encode(envelope)
        return String(decoding: data, as: UTF8.self)
    }
}

private struct HookPayload: Encodable {
    let hookEventName: String
    let sessionID: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionID = "session_id"
        case message
    }
}

private struct HookEnvelope: Encodable {
    let capturedAt: String
    let payloadBase64: String

    enum CodingKeys: String, CodingKey {
        case capturedAt = "captured_at"
        case payloadBase64 = "payload_base64"
    }
}
