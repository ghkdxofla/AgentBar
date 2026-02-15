import XCTest
@testable import AgentBar

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
        let suiteName = "AgentBarTests.AgentAlertMonitor.SameTimestamp.\(UUID().uuidString)"
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
        let suiteName = "AgentBarTests.AgentAlertMonitor.DisabledSetting.\(UUID().uuidString)"
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

    func testLegacyWatermarkWithoutEventIDsDoesNotReplayBoundaryEvents() async throws {
        let suiteName = "AgentBarTests.AgentAlertMonitor.LegacyWatermarkMigration.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "alertsEnabled")

        guard let watermarkTimestamp = DateUtils.parseISO8601("2026-02-15T13:00:00Z") else {
            XCTFail("Failed to create watermark timestamp")
            return
        }
        let newerTimestamp = watermarkTimestamp.addingTimeInterval(1)

        defaults.set(watermarkTimestamp.timeIntervalSince1970, forKey: watermarkKey(for: .codex))
        defaults.removeObject(forKey: watermarkEventIDsKey(for: .codex))

        let boundaryEvent = AgentAlertEvent(
            service: .codex,
            type: .taskCompleted,
            timestamp: watermarkTimestamp,
            message: nil,
            sessionID: "legacy-session"
        )
        let newerEvent = AgentAlertEvent(
            service: .codex,
            type: .permissionRequired,
            timestamp: newerTimestamp,
            message: "Codex requested elevated command permissions.",
            sessionID: "legacy-session"
        )

        let detector = BoundaryAwareTestAgentAlertDetector(events: [boundaryEvent, newerEvent])
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
        XCTAssertEqual(postedEvents.count, 1)
        XCTAssertEqual(postedEvents.first?.type, .permissionRequired)
        XCTAssertEqual(postedEvents.first?.timestamp, newerTimestamp)

        let includeBoundaryCalls = await detector.includeBoundaryCalls()
        XCTAssertEqual(includeBoundaryCalls, [false, true])
    }

    func testLegacyCursorIDsDoNotReplayBoundaryEventsAfterUpgrade() async throws {
        let suiteName = "AgentBarTests.AgentAlertMonitor.LegacyCursorMigration.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "alertsEnabled")

        guard let watermarkTimestamp = DateUtils.parseISO8601("2026-02-15T14:00:00Z") else {
            XCTFail("Failed to create watermark timestamp")
            return
        }

        let boundaryEvent = AgentAlertEvent(
            service: .codex,
            type: .permissionRequired,
            timestamp: watermarkTimestamp,
            message: "Codex requested elevated command permissions.",
            sessionID: "legacy-session",
            sourceRecordID: "legacy-session#42"
        )
        XCTAssertNotEqual(boundaryEvent.cursorID, boundaryEvent.legacyCursorID)

        defaults.set(watermarkTimestamp.timeIntervalSince1970, forKey: watermarkKey(for: .codex))
        defaults.set([boundaryEvent.legacyCursorID], forKey: watermarkEventIDsKey(for: .codex))
        defaults.set(1, forKey: watermarkSchemaVersionKey(for: .codex))

        let detector = BoundaryAwareTestAgentAlertDetector(events: [boundaryEvent])
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
        XCTAssertTrue(postedEvents.isEmpty)

        let includeBoundaryCalls = await detector.includeBoundaryCalls()
        XCTAssertEqual(includeBoundaryCalls, [true, true])

        let storedIDs = defaults.stringArray(forKey: watermarkEventIDsKey(for: .codex)) ?? []
        XCTAssertTrue(storedIDs.contains(boundaryEvent.cursorID))
        XCTAssertEqual(defaults.integer(forKey: watermarkSchemaVersionKey(for: .codex)), 2)
    }

    func testCooldownSuppressesRepeatedNotificationsForSameDedupeKey() async throws {
        let suiteName = "AgentBarTests.AgentAlertMonitor.Cooldown.\(UUID().uuidString)"
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

    func testSkipsDetectorWhenSourceToggleDisabled() async throws {
        let suiteName = "AgentBarTests.AgentAlertMonitor.SourceToggle.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "alertsEnabled")
        defaults.set(false, forKey: "alertClaudeHookEventsEnabled")

        let event = AgentAlertEvent(
            service: .claude,
            type: .taskCompleted,
            timestamp: Date(timeIntervalSince1970: 1_739_616_000),
            message: "Task completed.",
            sessionID: "session-4"
        )

        let detector = ToggleAwareTestAgentAlertDetector(
            serviceType: .claude,
            settingsEnabledKey: "alertClaudeHookEventsEnabled",
            batches: [[event]]
        )
        let notificationService = TestAgentAlertNotificationService()
        let monitor = AgentAlertMonitor(
            detectors: [detector],
            notificationService: notificationService,
            defaults: defaults,
            cooldown: 0
        )

        await monitor.processTick()

        let postedEvents = await notificationService.postedEvents()
        let detectCount = await detector.detectCallCount()
        XCTAssertTrue(postedEvents.isEmpty)
        XCTAssertEqual(detectCount, 0)
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

    private func watermarkSchemaVersionKey(for service: ServiceType) -> String {
        "\(watermarkKey(for: service))_cursorSchemaVersion"
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

private actor BoundaryAwareTestAgentAlertDetector: AgentAlertEventDetectorProtocol {
    nonisolated let serviceType: ServiceType = .codex

    private let events: [AgentAlertEvent]
    private var includeBoundaryHistory: [Bool] = []

    init(events: [AgentAlertEvent]) {
        self.events = events
    }

    func detectEvents(since: Date, includeBoundary: Bool) async -> [AgentAlertEvent] {
        includeBoundaryHistory.append(includeBoundary)
        return events.filter { event in
            includeBoundary ? event.timestamp >= since : event.timestamp > since
        }
    }

    func includeBoundaryCalls() -> [Bool] {
        includeBoundaryHistory
    }
}

private actor ToggleAwareTestAgentAlertDetector: AgentAlertEventDetectorProtocol {
    nonisolated let serviceType: ServiceType
    nonisolated let settingsEnabledKey: String?

    private var batches: [[AgentAlertEvent]]
    private var calls: Int = 0

    init(
        serviceType: ServiceType,
        settingsEnabledKey: String?,
        batches: [[AgentAlertEvent]]
    ) {
        self.serviceType = serviceType
        self.settingsEnabledKey = settingsEnabledKey
        self.batches = batches
    }

    func detectEvents(since: Date, includeBoundary: Bool) async -> [AgentAlertEvent] {
        calls += 1
        guard !batches.isEmpty else { return [] }
        return batches.removeFirst()
    }

    func detectCallCount() -> Int {
        calls
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

final class AgentAlertNotificationServiceTests: XCTestCase {
    func testPostUsesRedactedBodyWhenMessagePreviewDisabled() async throws {
        let suiteName = "AgentBarTests.AgentAlertNotificationService.Redacted.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: "alertShowMessagePreview")

        let recorder = NotificationBodyRecorder()
        let service = AgentAlertNotificationService(
            defaults: defaults,
            postBodyOverride: { body in
                recorder.append(body)
            }
        )

        let event = AgentAlertEvent(
            service: .codex,
            type: .decisionRequired,
            timestamp: Date(timeIntervalSince1970: 1),
            message: "Should I proceed with the schema migration?",
            sessionID: "session-1"
        )
        await service.post(event: event)

        XCTAssertEqual(recorder.bodies(), ["[\(event.service.rawValue)] Agent is waiting for your input."])
    }

    func testPostUsesMessagePreviewWhenEnabled() async throws {
        let suiteName = "AgentBarTests.AgentAlertNotificationService.Preview.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: "alertShowMessagePreview")

        let recorder = NotificationBodyRecorder()
        let service = AgentAlertNotificationService(
            defaults: defaults,
            postBodyOverride: { body in
                recorder.append(body)
            }
        )

        let event = AgentAlertEvent(
            service: .codex,
            type: .decisionRequired,
            timestamp: Date(timeIntervalSince1970: 1),
            message: "Should I proceed with the schema migration?",
            sessionID: "session-1"
        )
        await service.post(event: event)

        XCTAssertEqual(recorder.bodies(), ["[\(event.service.rawValue)] Should I proceed with the schema migration?"])
    }
}

final class AgentAlertEventTests: XCTestCase {
    func testCursorIDDiffersWhenSourceRecordIDDiffers() {
        let timestamp = Date(timeIntervalSince1970: 1_739_616_000)
        let first = AgentAlertEvent(
            service: .codex,
            type: .permissionRequired,
            timestamp: timestamp,
            message: "Codex requested elevated command permissions.",
            sessionID: "session-1",
            sourceRecordID: "session-1#12"
        )
        let second = AgentAlertEvent(
            service: .codex,
            type: .permissionRequired,
            timestamp: timestamp,
            message: "Codex requested elevated command permissions.",
            sessionID: "session-1",
            sourceRecordID: "session-1#13"
        )

        XCTAssertNotEqual(first.cursorID, second.cursorID)
    }
}

private final class NotificationBodyRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedBodies: [String] = []

    func append(_ body: String) {
        lock.lock()
        capturedBodies.append(body)
        lock.unlock()
    }

    func bodies() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return capturedBodies
    }
}
