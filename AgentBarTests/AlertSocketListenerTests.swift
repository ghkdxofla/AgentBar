import XCTest
@testable import AgentBar

final class AlertSocketListenerTests: XCTestCase {
    func testMapsStopEventToTaskCompleted() {
        XCTAssertEqual(AlertSocketListener.mapEventType("stop"), .taskCompleted)
    }

    func testMapsSubagentStopEventToTaskCompleted() {
        XCTAssertEqual(AlertSocketListener.mapEventType("subagent_stop"), .taskCompleted)
    }

    func testMapsPermissionEventToPermissionRequired() {
        XCTAssertEqual(AlertSocketListener.mapEventType("permission"), .permissionRequired)
    }

    func testMapsDecisionEventToDecisionRequired() {
        XCTAssertEqual(AlertSocketListener.mapEventType("decision"), .decisionRequired)
    }

    func testReturnsNilForUnknownEventType() {
        XCTAssertNil(AlertSocketListener.mapEventType("unknown"))
    }

    func testMapsCaseInsensitiveEventType() {
        XCTAssertEqual(AlertSocketListener.mapEventType("STOP"), .taskCompleted)
        XCTAssertEqual(AlertSocketListener.mapEventType("Permission"), .permissionRequired)
    }

    func testMapsClaudeAgentToServiceType() {
        XCTAssertEqual(AlertSocketListener.mapAgent("claude"), .claude)
    }

    func testMapsCodexAgentToServiceType() {
        XCTAssertEqual(AlertSocketListener.mapAgent("codex"), .codex)
    }

    func testMapsGeminiAgentToServiceType() {
        XCTAssertEqual(AlertSocketListener.mapAgent("gemini"), .gemini)
    }

    func testMapsCopilotAgentToServiceType() {
        XCTAssertEqual(AlertSocketListener.mapAgent("copilot"), .copilot)
    }

    func testMapsCursorAgentToServiceType() {
        XCTAssertEqual(AlertSocketListener.mapAgent("cursor"), .cursor)
    }

    func testMapsZaiAgentToServiceType() {
        XCTAssertEqual(AlertSocketListener.mapAgent("zai"), .zai)
    }

    func testReturnsNilForUnknownAgent() {
        XCTAssertNil(AlertSocketListener.mapAgent("unknown_agent"))
    }

    func testMapsAgentCaseInsensitive() {
        XCTAssertEqual(AlertSocketListener.mapAgent("Claude"), .claude)
        XCTAssertEqual(AlertSocketListener.mapAgent("CODEX"), .codex)
    }

    func testSocketAlertEventDecoding() throws {
        let json = """
        {"agent":"claude","event":"stop","session_id":"sess-1","message":"done","timestamp":"2026-02-16T10:00:00Z"}
        """
        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(SocketAlertEvent.self, from: data)

        XCTAssertEqual(event.agent, "claude")
        XCTAssertEqual(event.event, "stop")
        XCTAssertEqual(event.sessionID, "sess-1")
        XCTAssertEqual(event.message, "done")
        XCTAssertEqual(event.timestamp, "2026-02-16T10:00:00Z")
    }

    func testSocketAlertEventDecodingMinimalFields() throws {
        let json = """
        {"agent":"codex","event":"permission"}
        """
        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(SocketAlertEvent.self, from: data)

        XCTAssertEqual(event.agent, "codex")
        XCTAssertEqual(event.event, "permission")
        XCTAssertNil(event.sessionID)
        XCTAssertNil(event.message)
        XCTAssertNil(event.timestamp)
    }

    func testMalformedJSONDoesNotCrash() {
        let json = "not valid json at all"
        let data = json.data(using: .utf8)!
        let event = try? JSONDecoder().decode(SocketAlertEvent.self, from: data)
        XCTAssertNil(event)
    }
}

@MainActor
final class AgentAlertMonitorSocketReceiveTests: XCTestCase {
    func testReceivePostsNotificationForEnabledEvent() async throws {
        let suiteName = "AgentBarTests.MonitorReceive.Enabled.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "alertsEnabled")

        let notificationService = TestSocketNotificationService()
        let monitor = AgentAlertMonitor(
            detectors: [],
            notificationService: notificationService,
            defaults: defaults,
            cooldown: 0
        )

        let event = AgentAlertEvent(
            service: .claude,
            type: .taskCompleted,
            timestamp: Date(),
            message: "Task done",
            sessionID: "session-1"
        )

        await monitor.receive(event: event)

        let postedEvents = await notificationService.postedEvents()
        XCTAssertEqual(postedEvents.count, 1)
        XCTAssertEqual(postedEvents.first?.type, .taskCompleted)
    }

    func testReceiveRespectsEventTypeDisabled() async throws {
        let suiteName = "AgentBarTests.MonitorReceive.TypeDisabled.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "alertsEnabled")
        defaults.set(false, forKey: AgentAlertEventType.taskCompleted.settingsKey)

        let notificationService = TestSocketNotificationService()
        let monitor = AgentAlertMonitor(
            detectors: [],
            notificationService: notificationService,
            defaults: defaults,
            cooldown: 0
        )

        let event = AgentAlertEvent(
            service: .claude,
            type: .taskCompleted,
            timestamp: Date(),
            message: "Task done",
            sessionID: "session-1"
        )

        await monitor.receive(event: event)

        let postedEvents = await notificationService.postedEvents()
        XCTAssertTrue(postedEvents.isEmpty)
    }

    func testReceiveRespectsCooldown() async throws {
        let suiteName = "AgentBarTests.MonitorReceive.Cooldown.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "alertsEnabled")

        let notificationService = TestSocketNotificationService()
        let monitor = AgentAlertMonitor(
            detectors: [],
            notificationService: notificationService,
            defaults: defaults,
            cooldown: 90
        )

        let event = AgentAlertEvent(
            service: .claude,
            type: .taskCompleted,
            timestamp: Date(),
            message: nil,
            sessionID: "session-1"
        )

        await monitor.receive(event: event)
        await monitor.receive(event: event)

        let postedEvents = await notificationService.postedEvents()
        XCTAssertEqual(postedEvents.count, 1)
    }

    func testReceiveRespectsSourceToggle() async throws {
        let suiteName = "AgentBarTests.MonitorReceive.SourceToggle.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "alertsEnabled")
        defaults.set(false, forKey: "alertClaudeHookEventsEnabled")

        let notificationService = TestSocketNotificationService()
        let monitor = AgentAlertMonitor(
            detectors: [],
            notificationService: notificationService,
            defaults: defaults,
            cooldown: 0
        )

        let event = AgentAlertEvent(
            service: .claude,
            type: .taskCompleted,
            timestamp: Date(),
            message: "Task done",
            sessionID: "session-1"
        )

        await monitor.receive(event: event)

        let postedEvents = await notificationService.postedEvents()
        XCTAssertTrue(postedEvents.isEmpty)
    }

    func testReceiveIgnoresWhenAlertsDisabled() async throws {
        let suiteName = "AgentBarTests.MonitorReceive.AlertsOff.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: "alertsEnabled")

        let notificationService = TestSocketNotificationService()
        let monitor = AgentAlertMonitor(
            detectors: [],
            notificationService: notificationService,
            defaults: defaults,
            cooldown: 0
        )

        let event = AgentAlertEvent(
            service: .claude,
            type: .taskCompleted,
            timestamp: Date(),
            message: "Task done",
            sessionID: "session-1"
        )

        await monitor.receive(event: event)

        let postedEvents = await notificationService.postedEvents()
        XCTAssertTrue(postedEvents.isEmpty)
    }
}

private actor TestSocketNotificationService: AgentAlertNotificationServiceProtocol {
    private var events: [AgentAlertEvent] = []

    func requestAuthorizationIfNeeded() async {}

    func post(event: AgentAlertEvent) async {
        events.append(event)
    }

    func postedEvents() -> [AgentAlertEvent] {
        events
    }
}
