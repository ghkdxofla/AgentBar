import XCTest
import UserNotifications
@testable import AgentBar

final class AgentNotifyNotificationServiceBehaviorTests: XCTestCase {
    func testRequestAuthorizationIfNeededPromptsOnceWhenNotDetermined() async {
        let recorder = AuthorizationRecorder(status: UNAuthorizationStatus.notDetermined.rawValue)

        let service = AgentNotifyNotificationService(
            authorizationStatusOverride: {
                await recorder.recordStatusCheck()
                return await recorder.statusValue()
            },
            requestAuthorizationOverride: {
                await recorder.recordRequest()
                return true
            }
        )

        await service.requestAuthorizationIfNeeded()
        await service.requestAuthorizationIfNeeded()

        let statusChecks = await recorder.statusChecks()
        let requestCount = await recorder.requestCount()
        XCTAssertEqual(statusChecks, 1)
        XCTAssertEqual(requestCount, 1)
    }

    func testRequestAuthorizationIfNeededSkipsPromptWhenAlreadyDetermined() async {
        let recorder = AuthorizationRecorder(status: UNAuthorizationStatus.authorized.rawValue)

        let service = AgentNotifyNotificationService(
            authorizationStatusOverride: {
                await recorder.recordStatusCheck()
                return await recorder.statusValue()
            },
            requestAuthorizationOverride: {
                await recorder.recordRequest()
                return true
            }
        )

        await service.requestAuthorizationIfNeeded()

        let statusChecks = await recorder.statusChecks()
        let requestCount = await recorder.requestCount()
        XCTAssertEqual(statusChecks, 1)
        XCTAssertEqual(requestCount, 0)
    }

    func testPostUsesAddRequestOverrideWhenNoPostOverridesProvided() async {
        let suiteName = "AgentBarTests.AgentNotifyNotificationService.AddOverride.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: "notificationShowMessagePreview")

        let recorder = PostedRequestRecorder()
        let service = AgentNotifyNotificationService(
            defaults: defaults,
            addRequestOverride: { request in
                await recorder.record(
                    identifier: request.identifier,
                    title: request.content.title,
                    body: request.content.body,
                    hasSound: request.content.sound != nil
                )
            }
        )

        let event = AgentNotifyEvent(
            service: .codex,
            type: .decisionRequired,
            timestamp: Date(timeIntervalSince1970: 10),
            message: "Please review this schema migration.",
            sessionID: "session-1"
        )

        await service.post(event: event)

        let payload = await recorder.singlePayload()
        XCTAssertTrue(payload.identifier.hasPrefix("agentbar-agent-notify-"))
        XCTAssertEqual(payload.title, "OpenAI Codex")
        XCTAssertEqual(payload.body, "Input required: Agent is waiting for your input.")
    }

    func testPostMutesSoundWhenSoundModeIsMute() async {
        let suiteName = "AgentBarTests.AgentNotifyNotificationService.Mute.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(NotificationSoundMode.mute.rawValue, forKey: NotificationSoundMode.defaultsKey)

        let recorder = PostedRequestRecorder()
        let service = AgentNotifyNotificationService(
            defaults: defaults,
            addRequestOverride: { request in
                await recorder.record(
                    identifier: request.identifier,
                    title: request.content.title,
                    body: request.content.body,
                    hasSound: request.content.sound != nil
                )
            }
        )

        let event = AgentNotifyEvent(
            service: .claude,
            type: .taskCompleted,
            timestamp: Date(timeIntervalSince1970: 20),
            message: "done",
            sessionID: "session-2"
        )

        await service.post(event: event)

        let payload = await recorder.singlePayload()
        XCTAssertFalse(payload.hasSound)
    }

    func testPostSwallowsAddRequestErrors() async {
        let recorder = ErrorPathRecorder()
        let service = AgentNotifyNotificationService(
            addRequestOverride: { _ in
                await recorder.recordAttempt()
                throw StubAddError.failed
            }
        )

        let event = AgentNotifyEvent(
            service: .claude,
            type: .taskCompleted,
            timestamp: Date(timeIntervalSince1970: 20),
            message: nil,
            sessionID: "session-2"
        )

        await service.post(event: event)
        let attempts = await recorder.attempts()
        XCTAssertEqual(attempts, 1)
    }

    #if AGENTBAR_NOTIFICATION_SOUNDS
    func testPostPlaysCustomSoundAfterNotificationRequestAdded() async {
        let suiteName = "AgentBarTests.AgentNotifyNotificationService.CustomSoundOrder.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let requestRecorder = PostedRequestRecorder()
        let callOrder = CallOrderRecorder()

        let service = AgentNotifyNotificationService(
            defaults: defaults,
            addRequestOverride: { request in
                callOrder.record("add")
                await requestRecorder.record(
                    identifier: request.identifier,
                    title: request.content.title,
                    body: request.content.body,
                    hasSound: request.content.sound != nil
                )
            },
            shouldUseCustomSoundOverride: { _ in true },
            playCustomSoundOverride: { _ in
                callOrder.record("play")
                return true
            }
        )

        let event = AgentNotifyEvent(
            service: .codex,
            type: .taskCompleted,
            timestamp: Date(timeIntervalSince1970: 30),
            message: "done",
            sessionID: "session-3"
        )

        await service.post(event: event)

        let payload = await requestRecorder.singlePayload()
        XCTAssertFalse(payload.hasSound)
        XCTAssertEqual(callOrder.snapshot(), ["add", "play"])
    }

    func testPostTriggersFallbackSoundWhenCustomPlaybackFails() async {
        let suiteName = "AgentBarTests.AgentNotifyNotificationService.CustomSoundFallback.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let requestRecorder = PostedRequestRecorder()
        let callOrder = CallOrderRecorder()

        let service = AgentNotifyNotificationService(
            defaults: defaults,
            addRequestOverride: { request in
                callOrder.record("add")
                await requestRecorder.record(
                    identifier: request.identifier,
                    title: request.content.title,
                    body: request.content.body,
                    hasSound: request.content.sound != nil
                )
            },
            shouldUseCustomSoundOverride: { _ in true },
            playCustomSoundOverride: { _ in
                callOrder.record("play")
                return false
            },
            playFallbackSoundOverride: {
                callOrder.record("fallback")
            }
        )

        let event = AgentNotifyEvent(
            service: .claude,
            type: .decisionRequired,
            timestamp: Date(timeIntervalSince1970: 40),
            message: "Need input",
            sessionID: "session-4"
        )

        await service.post(event: event)

        let payload = await requestRecorder.singlePayload()
        XCTAssertFalse(payload.hasSound)
        XCTAssertEqual(callOrder.snapshot(), ["add", "play", "fallback"])
    }
    #endif
}

private actor AuthorizationRecorder {
    private let status: Int
    private var statusCheckCounter: Int = 0
    private var requestCounter: Int = 0

    init(status: Int) {
        self.status = status
    }

    func recordStatusCheck() {
        statusCheckCounter += 1
    }

    func recordRequest() {
        requestCounter += 1
    }

    func statusValue() -> Int {
        status
    }

    func statusChecks() -> Int {
        statusCheckCounter
    }

    func requestCount() -> Int {
        requestCounter
    }
}

private actor PostedRequestRecorder {
    private var payloads: [(identifier: String, title: String, body: String, hasSound: Bool)] = []

    func record(identifier: String, title: String, body: String, hasSound: Bool) {
        payloads.append((identifier, title, body, hasSound))
    }

    func singlePayload() -> (identifier: String, title: String, body: String, hasSound: Bool) {
        payloads[0]
    }
}

private actor ErrorPathRecorder {
    private var count: Int = 0

    func recordAttempt() {
        count += 1
    }

    func attempts() -> Int {
        count
    }
}

private enum StubAddError: Error {
    case failed
}

private final class CallOrderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []

    func record(_ value: String) {
        lock.lock()
        calls.append(value)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        let copied = calls
        lock.unlock()
        return copied
    }
}
