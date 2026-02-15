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

    func testIncludesEventsAtWatermarkWhenBoundaryIncluded() async throws {
        let file = try makeSessionFile(named: "rollout-watermark-inclusive.jsonl")
        let line = """
        {"timestamp":"2026-02-15T10:00:00Z","type":"event_msg","payload":{"type":"task_complete"}}
        """
        try line.write(to: file, atomically: true, encoding: .utf8)

        guard let watermark = DateUtils.parseISO8601("2026-02-15T10:00:00Z") else {
            XCTFail("Failed to create watermark date")
            return
        }

        let detector = CodexAlertEventDetector(sessionsDir: tempDir)
        let events = await detector.detectEvents(since: watermark, includeBoundary: true)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .taskCompleted)
    }

    func testDetectsPermissionRequiredFromMalformedArgumentsContainingEscalation() async throws {
        let file = try makeSessionFile(named: "rollout-permission-malformed.jsonl")
        let line = #"""
        {"timestamp":"2026-02-15T10:00:00Z","type":"response_item","payload":{"type":"function_call","arguments":"{\"cmd\":\"xcodebuild test\",\n\t\"sandbox_permissions\" : \"require_escalated\""}}
        """#
        try line.write(to: file, atomically: true, encoding: .utf8)

        let detector = CodexAlertEventDetector(sessionsDir: tempDir)
        let events = await detector.detectEvents(since: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .permissionRequired)
    }

    func testDoesNotDetectPermissionRequiredWithoutEscalationFlag() async throws {
        let file = try makeSessionFile(named: "rollout-permission-non-escalated.jsonl")
        let line = #"""
        {"timestamp":"2026-02-15T10:00:00Z","type":"response_item","payload":{"type":"function_call","arguments":"{\"cmd\":\"xcodebuild test\",\"sandbox_permissions\":\"use_default\"}"}}
        """#
        try line.write(to: file, atomically: true, encoding: .utf8)

        let detector = CodexAlertEventDetector(sessionsDir: tempDir)
        let events = await detector.detectEvents(since: Date(timeIntervalSince1970: 0))

        XCTAssertTrue(events.isEmpty)
    }

    private func makeSessionFile(named filename: String) throws -> URL {
        let dateDir = tempDir.appendingPathComponent("2026/02/15")
        try FileManager.default.createDirectory(at: dateDir, withIntermediateDirectories: true)
        return dateDir.appendingPathComponent(filename)
    }
}

@MainActor
final class AgentAlertMonitorTests: XCTestCase {
    func testProcessesNewEventWithSameTimestampAcrossPollingCycles() async throws {
        let suiteName = "CCUsageBarTests.AgentAlertMonitor.SameTimestamp.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "alertsEnabled")

        guard let timestamp = DateUtils.parseISO8601("2026-02-15T10:00:00Z") else {
            XCTFail("Failed to create timestamp")
            return
        }

        let first = AgentAlertEvent(
            service: .codex,
            type: .taskCompleted,
            timestamp: timestamp,
            message: nil,
            sessionID: "session-1"
        )
        let second = AgentAlertEvent(
            service: .codex,
            type: .permissionRequired,
            timestamp: timestamp,
            message: "Codex requested elevated command permissions.",
            sessionID: "session-1"
        )

        let detector = TestAgentAlertDetector(batches: [[first], [first, second]])
        let notificationService = TestAgentAlertNotificationService()
        let monitor = AgentAlertMonitor(
            detectors: [detector],
            notificationService: notificationService,
            defaults: defaults,
            cooldown: 0
        )

        await monitor.processTick()
        await monitor.processTick()

        let postedEvents = await notificationService.postedEvents()
        let includeBoundaryCalls = await detector.includeBoundaryCalls()
        XCTAssertEqual(postedEvents.map(\.type), [.taskCompleted, .permissionRequired])
        XCTAssertEqual(includeBoundaryCalls, [true, true])

        let watermarkIDs = defaults.stringArray(forKey: watermarkEventIDsKey(for: .codex)) ?? []
        XCTAssertEqual(Set(watermarkIDs).count, 2)
    }

    func testDisabledEventStillAdvancesWatermarkAndAvoidsFutureDuplicateNotification() async throws {
        let suiteName = "CCUsageBarTests.AgentAlertMonitor.DisabledSetting.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "alertsEnabled")
        defaults.set(false, forKey: AgentAlertEventType.decisionRequired.settingsKey)

        guard let timestamp = DateUtils.parseISO8601("2026-02-15T11:00:00Z") else {
            XCTFail("Failed to create timestamp")
            return
        }

        let decisionEvent = AgentAlertEvent(
            service: .codex,
            type: .decisionRequired,
            timestamp: timestamp,
            message: "Should I proceed?",
            sessionID: "session-2"
        )

        let detector = TestAgentAlertDetector(batches: [[decisionEvent], [decisionEvent]])
        let notificationService = TestAgentAlertNotificationService()
        let monitor = AgentAlertMonitor(
            detectors: [detector],
            notificationService: notificationService,
            defaults: defaults,
            cooldown: 0
        )

        await monitor.processTick()
        defaults.set(true, forKey: AgentAlertEventType.decisionRequired.settingsKey)
        await monitor.processTick()

        let postedEvents = await notificationService.postedEvents()
        XCTAssertTrue(postedEvents.isEmpty)
    }

    func testCooldownSuppressesRepeatedNotificationsForSameDedupeKey() async throws {
        let suiteName = "CCUsageBarTests.AgentAlertMonitor.Cooldown.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "alertsEnabled")

        guard let firstTime = DateUtils.parseISO8601("2026-02-15T12:00:00Z"),
              let secondTime = DateUtils.parseISO8601("2026-02-15T12:00:01Z") else {
            XCTFail("Failed to create timestamps")
            return
        }

        let first = AgentAlertEvent(
            service: .codex,
            type: .taskCompleted,
            timestamp: firstTime,
            message: nil,
            sessionID: "session-3"
        )
        let second = AgentAlertEvent(
            service: .codex,
            type: .taskCompleted,
            timestamp: secondTime,
            message: nil,
            sessionID: "session-3"
        )

        let detector = TestAgentAlertDetector(batches: [[first], [second]])
        let notificationService = TestAgentAlertNotificationService()
        let monitor = AgentAlertMonitor(
            detectors: [detector],
            notificationService: notificationService,
            defaults: defaults,
            cooldown: 90
        )

        await monitor.processTick()
        await monitor.processTick()

        let postedEvents = await notificationService.postedEvents()
        XCTAssertEqual(postedEvents.count, 1)
        XCTAssertEqual(postedEvents.first?.type, .taskCompleted)

        let watermark = defaults.double(forKey: watermarkKey(for: .codex))
        XCTAssertEqual(watermark, secondTime.timeIntervalSince1970, accuracy: 0.000_001)
    }

    private func watermarkKey(for service: ServiceType) -> String {
        let normalized = service.rawValue
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        return "alertLastSeen_\(normalized)"
    }

    private func watermarkEventIDsKey(for service: ServiceType) -> String {
        "\(watermarkKey(for: service))_eventIDs"
    }
}

private actor TestAgentAlertDetector: AgentAlertEventDetectorProtocol {
    nonisolated let serviceType: ServiceType = .codex

    private var batches: [[AgentAlertEvent]]
    private var includeBoundaryHistory: [Bool] = []

    init(batches: [[AgentAlertEvent]]) {
        self.batches = batches
    }

    func detectEvents(since: Date, includeBoundary: Bool) async -> [AgentAlertEvent] {
        includeBoundaryHistory.append(includeBoundary)
        guard !batches.isEmpty else { return [] }
        return batches.removeFirst()
    }

    func includeBoundaryCalls() -> [Bool] {
        includeBoundaryHistory
    }
}

private actor TestAgentAlertNotificationService: AgentAlertNotificationServiceProtocol {
    private var events: [AgentAlertEvent] = []

    func requestAuthorizationIfNeeded() async {}

    func post(event: AgentAlertEvent) async {
        events.append(event)
    }

    func postedEvents() -> [AgentAlertEvent] {
        events
    }
}
