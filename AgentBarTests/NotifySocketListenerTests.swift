import XCTest
@testable import AgentBar
import Darwin

final class NotifySocketListenerTests: XCTestCase {
    func testMapsStopEventToTaskCompleted() {
        XCTAssertEqual(NotifySocketListener.mapEventType("stop"), .taskCompleted)
    }

    func testMapsSubagentStopEventToTaskCompleted() {
        XCTAssertEqual(NotifySocketListener.mapEventType("subagent_stop"), .taskCompleted)
    }

    func testMapsPermissionEventToPermissionRequired() {
        XCTAssertEqual(NotifySocketListener.mapEventType("permission"), .permissionRequired)
    }

    func testMapsDecisionEventToDecisionRequired() {
        XCTAssertEqual(NotifySocketListener.mapEventType("decision"), .decisionRequired)
    }

    func testReturnsNilForUnknownEventType() {
        XCTAssertNil(NotifySocketListener.mapEventType("unknown"))
    }

    func testMapsCaseInsensitiveEventType() {
        XCTAssertEqual(NotifySocketListener.mapEventType("STOP"), .taskCompleted)
        XCTAssertEqual(NotifySocketListener.mapEventType("Permission"), .permissionRequired)
    }

    func testMapsClaudeAgentToServiceType() {
        XCTAssertEqual(NotifySocketListener.mapAgent("claude"), .claude)
    }

    func testMapsCodexAgentToServiceType() {
        XCTAssertEqual(NotifySocketListener.mapAgent("codex"), .codex)
    }

    func testMapsGeminiAgentToServiceType() {
        XCTAssertEqual(NotifySocketListener.mapAgent("gemini"), .gemini)
    }

    func testMapsCopilotAgentToServiceType() {
        XCTAssertEqual(NotifySocketListener.mapAgent("copilot"), .copilot)
    }

    func testMapsCursorAgentToServiceType() {
        XCTAssertEqual(NotifySocketListener.mapAgent("cursor"), .cursor)
    }

    func testMapsOpencodeAgentAliasToServiceType() {
        XCTAssertEqual(NotifySocketListener.mapAgent("opencode"), .opencode)
    }

    func testMapsZaiAgentToServiceType() {
        XCTAssertEqual(NotifySocketListener.mapAgent("zai"), .zai)
    }

    func testReturnsNilForUnknownAgent() {
        XCTAssertNil(NotifySocketListener.mapAgent("unknown_agent"))
    }

    func testMapsAgentCaseInsensitive() {
        XCTAssertEqual(NotifySocketListener.mapAgent("Claude"), .claude)
        XCTAssertEqual(NotifySocketListener.mapAgent("CODEX"), .codex)
    }

    func testSocketNotifyEventDecoding() throws {
        let json = """
        {"agent":"claude","event":"stop","session_id":"sess-1","message":"done","timestamp":"2026-02-16T10:00:00Z"}
        """
        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(SocketNotifyEvent.self, from: data)

        XCTAssertEqual(event.agent, "claude")
        XCTAssertEqual(event.event, "stop")
        XCTAssertEqual(event.sessionID, "sess-1")
        XCTAssertEqual(event.message, "done")
        XCTAssertEqual(event.timestamp, "2026-02-16T10:00:00Z")
    }

    func testSocketNotifyEventDecodingMinimalFields() throws {
        let json = """
        {"agent":"codex","event":"permission"}
        """
        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(SocketNotifyEvent.self, from: data)

        XCTAssertEqual(event.agent, "codex")
        XCTAssertEqual(event.event, "permission")
        XCTAssertNil(event.sessionID)
        XCTAssertNil(event.message)
        XCTAssertNil(event.timestamp)
    }

    func testMalformedJSONDoesNotCrash() {
        let json = "not valid json at all"
        let data = json.data(using: .utf8)!
        let event = try? JSONDecoder().decode(SocketNotifyEvent.self, from: data)
        XCTAssertNil(event)
    }
}

final class NotifySocketListenerLifecycleTests: XCTestCase {
    private var tempDir: URL!

    private func waitUntil(
        timeout: TimeInterval,
        pollInterval: TimeInterval = 0.01,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(pollInterval))
        }
        return condition()
    }

    private func openClientSocket(to socketPath: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            return nil
        }

        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                for (index, byte) in pathBytes.enumerated() {
                    dest[index] = byte
                }
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, addrLen)
            }
        }

        guard result == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    private func canConnectAndDisconnect(to socketPath: String) -> Bool {
        guard let clientFD = openClientSocket(to: socketPath) else {
            return false
        }
        close(clientFD)
        return true
    }

    private func conditionRemainsTrue(
        duration: TimeInterval,
        pollInterval: TimeInterval = 0.02,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            guard condition() else { return false }
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(pollInterval))
        }
        return condition()
    }

    private func waitUntilStable(
        timeout: TimeInterval,
        stableDuration: TimeInterval,
        pollInterval: TimeInterval = 0.02,
        condition: () -> Bool
    ) -> Bool {
        waitUntil(timeout: timeout, pollInterval: pollInterval) {
            conditionRemainsTrue(duration: stableDuration, pollInterval: pollInterval) {
                condition()
            }
        }
    }

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

    func testStartSetsIsListeningAndStopClearsIt() {
        let sockPath = tempDir.appendingPathComponent("test.sock").path
        let listener = NotifySocketListener(socketPath: sockPath)

        XCTAssertFalse(listener.isListening)

        listener.start()
        XCTAssertTrue(listener.isListening)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sockPath))
        XCTAssertTrue(
            waitUntil(timeout: 1) {
                canConnectAndDisconnect(to: sockPath)
            },
            "Socket path did not become connectable after start()"
        )

        listener.stop()
        XCTAssertFalse(listener.isListening)
    }

    func testRapidRestartDoesNotCorruptState() {
        let sockPath = tempDir.appendingPathComponent("restart.sock").path
        let listener = NotifySocketListener(socketPath: sockPath)

        // Rapid start/stop cycles
        for _ in 0..<5 {
            listener.start()
            XCTAssertTrue(listener.isListening)
            listener.stop()
            XCTAssertFalse(listener.isListening)
        }

        // Final start should work
        listener.start()
        XCTAssertTrue(listener.isListening)
        listener.stop()
    }

    func testStartTwiceWithoutStopRetainsSocketPathAndAcceptsConnections() throws {
        let sockPath = tempDir.appendingPathComponent("double-start.sock").path
        let listener = NotifySocketListener(socketPath: sockPath)

        listener.start()
        XCTAssertTrue(listener.isListening)
        defer { listener.stop() }

        // Reentrant start() is implemented as stop+start and must leave a live socket.
        listener.start()
        XCTAssertTrue(listener.isListening)

        XCTAssertTrue(
            waitUntilStable(timeout: 1, stableDuration: 1) {
                canConnectAndDisconnect(to: sockPath)
            },
            "Socket path did not stay connectable for a full stability window after start() while already running"
        )

        XCTAssertTrue(
            waitUntil(timeout: 1) {
                listener.activeClientCountForTesting == 0
            },
            "Listener still had active probe clients before final acceptance check"
        )
        let clientFD = try XCTUnwrap(openClientSocket(to: sockPath))
        XCTAssertTrue(
            waitUntil(timeout: 1) {
                listener.activeClientCountForTesting >= 1
            },
            "Listener did not accept client after start() while already running"
        )
        close(clientFD)
    }

    func testStartWhileRunningWithActiveClientAllowsNewConnections() throws {
        let sockPath = tempDir.appendingPathComponent("b.sock").path
        let listener = NotifySocketListener(socketPath: sockPath)

        listener.start()
        XCTAssertTrue(listener.isListening)
        defer { listener.stop() }

        let firstClientFD = try XCTUnwrap(openClientSocket(to: sockPath))
        defer { close(firstClientFD) }

        XCTAssertTrue(
            waitUntilStable(timeout: 1, stableDuration: 0.2) {
                listener.activeClientCountForTesting >= 1
            },
            "Listener did not keep first client active before restart"
        )

        // Restart while a client is still connected.
        listener.start()
        XCTAssertTrue(listener.isListening)
        XCTAssertTrue(
            waitUntil(timeout: 1) {
                listener.activeClientCountForTesting == 0
            },
            "Listener did not clear prior clients during restart"
        )

        XCTAssertTrue(
            waitUntilStable(timeout: 1, stableDuration: 1) {
                canConnectAndDisconnect(to: sockPath)
            },
            "Socket path did not stay connectable for a full stability window after restart with active client"
        )
        XCTAssertTrue(
            waitUntil(timeout: 1) {
                listener.activeClientCountForTesting == 0
            },
            "Listener still had active probe clients before second acceptance check"
        )

        let secondClientFD = try XCTUnwrap(openClientSocket(to: sockPath))
        XCTAssertTrue(
            waitUntil(timeout: 1) {
                listener.activeClientCountForTesting >= 1
            },
            "Listener did not accept second client after restart"
        )
        close(secondClientFD)
    }

    func testStopWithoutStartIsNoOp() {
        let sockPath = tempDir.appendingPathComponent("noop.sock").path
        let listener = NotifySocketListener(socketPath: sockPath)

        // Should not crash
        listener.stop()
        XCTAssertFalse(listener.isListening)
    }

    func testDoubleStopIsNoOp() {
        let sockPath = tempDir.appendingPathComponent("double.sock").path
        let listener = NotifySocketListener(socketPath: sockPath)

        listener.start()
        listener.stop()
        listener.stop()
        XCTAssertFalse(listener.isListening)
    }

    func testIsListeningIsFalseImmediatelyAfterStop() {
        let sockPath = tempDir.appendingPathComponent("immediate.sock").path
        let listener = NotifySocketListener(socketPath: sockPath)

        listener.start()
        XCTAssertTrue(listener.isListening)

        // isListening must be false synchronously after stop() returns
        listener.stop()
        XCTAssertFalse(listener.isListening)
    }

    func testStopWithActiveClientAllowsCleanRestart() throws {
        let sockPath = tempDir.appendingPathComponent("a.sock").path
        let listener = NotifySocketListener(socketPath: sockPath)

        listener.start()
        XCTAssertTrue(listener.isListening)
        let clientFD = try XCTUnwrap(openClientSocket(to: sockPath))
        defer { close(clientFD) }

        let message = "{\"agent\":\"claude\",\"event\":\"stop\"}\n"
        _ = message.withCString { cString in
            write(clientFD, cString, strlen(cString))
        }

        listener.stop()
        XCTAssertFalse(listener.isListening)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sockPath))

        listener.start()
        XCTAssertTrue(listener.isListening)
        let restartedFD = try XCTUnwrap(openClientSocket(to: sockPath))
        close(restartedFD)
        listener.stop()
    }

    func testRestartRetainsSocketPathAndAcceptsConnections() throws {
        let sockPath = tempDir.appendingPathComponent("r.sock").path
        let listener = NotifySocketListener(socketPath: sockPath)

        listener.start()
        XCTAssertTrue(listener.isListening)
        listener.stop()
        listener.start()
        XCTAssertTrue(listener.isListening)

        XCTAssertTrue(
            waitUntilStable(timeout: 1, stableDuration: 1) {
                canConnectAndDisconnect(to: sockPath)
            },
            "Socket path did not stay connectable for a full stability window after restart"
        )
        listener.stop()
    }
}

final class HookScriptFallbackTests: XCTestCase {
    private var tempDir: URL!

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

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

    private func sourcePath(for command: String) throws -> String {
        let candidates = ["/usr/bin/\(command)", "/bin/\(command)"]
        if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return match
        }
        throw NSError(
            domain: "HookScriptFallbackTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Required command not found: \(command)"]
        )
    }

    private func makeToolsPathWithoutPython3() throws -> String {
        let binDir = tempDir.appendingPathComponent("tools-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

        for command in ["cat", "tr", "date", "nc", "mkdir", "base64", "perl"] {
            let source = try sourcePath(for: command)
            try FileManager.default.createSymbolicLink(
                atPath: binDir.appendingPathComponent(command).path,
                withDestinationPath: source
            )
        }

        return binDir.path
    }

    private func runScript(
        named scriptName: String,
        arguments: [String] = [],
        stdin: String? = nil,
        environmentOverrides: [String: String]
    ) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [repositoryRoot.appendingPathComponent("scripts/\(scriptName)").path] + arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        if stdin != nil {
            process.standardInput = stdinPipe
        }

        var env = ProcessInfo.processInfo.environment
        for (key, value) in environmentOverrides {
            env[key] = value
        }
        process.environment = env

        try process.run()
        if let stdin {
            stdinPipe.fileHandleForWriting.write(Data(stdin.utf8))
            stdinPipe.fileHandleForWriting.closeFile()
        }
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }

    private func waitForExit(of process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return !process.isRunning
    }

    private func captureSocketMessage(
        at socketPath: String,
        trigger: () throws -> Void
    ) throws -> String {
        let listener = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        try? FileManager.default.removeItem(atPath: socketPath)

        listener.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        listener.arguments = ["-lU", socketPath]
        listener.standardOutput = stdoutPipe
        listener.standardError = stderrPipe
        try listener.run()

        let readyDeadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: socketPath) && Date() < readyDeadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: socketPath), "Socket listener did not become ready")

        try trigger()

        if !waitForExit(of: listener, timeout: 2), listener.isRunning {
            listener.terminate()
            _ = waitForExit(of: listener, timeout: 1)
            XCTFail("Timed out waiting for socket listener to receive script output")
        }

        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(listener.terminationStatus, 0, "Socket listener failed: \(stderr)")

        let output = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseJSONObject(_ jsonText: String) throws -> [String: Any] {
        let data = try XCTUnwrap(jsonText.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    func testClaudeHookParsesAndEncodesWithoutPython3() throws {
        let socketPath = tempDir.appendingPathComponent("claude.sock").path
        let expectedMessage = "Need \"quotes\" and \\slashes\\\nnext line"
        let payloadData = try JSONSerialization.data(
            withJSONObject: [
                "hook_event_name": "Stop",
                "session_id": "sess-1",
                "message": expectedMessage
            ],
            options: []
        )
        let payload = try XCTUnwrap(String(data: payloadData, encoding: .utf8))
        let toolsPath = try makeToolsPathWithoutPython3()

        let jsonText = try captureSocketMessage(at: socketPath) {
            let result = try runScript(
                named: "agentbar-hook.sh",
                stdin: payload,
                environmentOverrides: [
                    "PATH": toolsPath,
                    "AGENTBAR_SOCKET": socketPath,
                    "AGENTBAR_CLAUDE_HOOK_LOG": tempDir.appendingPathComponent("unused.jsonl").path
                ]
            )
            XCTAssertEqual(result.status, 0, "Script failed: \(result.stderr)")
        }

        let decoded = try parseJSONObject(jsonText)
        XCTAssertEqual(decoded["agent"] as? String, "claude")
        XCTAssertEqual(decoded["event"] as? String, "stop")
        XCTAssertEqual(decoded["session_id"] as? String, "sess-1")
        XCTAssertEqual(decoded["message"] as? String, expectedMessage)
    }

    func testCodexHookEncodesWithoutPython3() throws {
        let socketPath = tempDir.appendingPathComponent("codex.sock").path
        let expectedMessage = "Decision needed: \"keep\" vs \\change\\\nline two"
        let toolsPath = try makeToolsPathWithoutPython3()

        let jsonText = try captureSocketMessage(at: socketPath) {
            let result = try runScript(
                named: "agentbar-codex-hook.sh",
                arguments: ["custom-event"],
                stdin: expectedMessage,
                environmentOverrides: [
                    "PATH": toolsPath,
                    "AGENTBAR_SOCKET": socketPath,
                    "CODEX_SESSION_ID": "codex-session-1"
                ]
            )
            XCTAssertEqual(result.status, 0, "Script failed: \(result.stderr)")
        }

        let decoded = try parseJSONObject(jsonText)
        XCTAssertEqual(decoded["agent"] as? String, "codex")
        XCTAssertEqual(decoded["event"] as? String, "stop")
        XCTAssertEqual(decoded["session_id"] as? String, "codex-session-1")
        XCTAssertEqual(decoded["message"] as? String, expectedMessage)
    }

    func testOpenCodeHookMapsPermissionAskedToDecisionWithoutPython3() throws {
        let socketPath = tempDir.appendingPathComponent("opencode.sock").path
        let payloadData = try JSONSerialization.data(
            withJSONObject: [
                "type": "permission.asked",
                "properties": [
                    "sessionID": "oc-session-1",
                    "permission": "Shell command"
                ]
            ],
            options: []
        )
        let payload = try XCTUnwrap(String(data: payloadData, encoding: .utf8))
        let toolsPath = try makeToolsPathWithoutPython3()

        let jsonText = try captureSocketMessage(at: socketPath) {
            let result = try runScript(
                named: "agentbar-opencode-hook.sh",
                stdin: payload,
                environmentOverrides: [
                    "PATH": toolsPath,
                    "AGENTBAR_SOCKET": socketPath
                ]
            )
            XCTAssertEqual(result.status, 0, "Script failed: \(result.stderr)")
        }

        let decoded = try parseJSONObject(jsonText)
        XCTAssertEqual(decoded["agent"] as? String, "opencode")
        XCTAssertEqual(decoded["event"] as? String, "decision")
        XCTAssertEqual(decoded["session_id"] as? String, "oc-session-1")
        XCTAssertEqual(decoded["message"] as? String, "Permission requested: Shell command")
    }
}

@MainActor
final class AgentNotifyMonitorSocketReceiveTests: XCTestCase {
    func testReceivePostsNotificationForEnabledEvent() async throws {
        let suiteName = "AgentBarTests.MonitorReceive.Enabled.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "notificationsEnabled")

        let notificationService = TestSocketNotifyService()
        let monitor = AgentNotifyMonitor(
            detectors: [],
            notificationService: notificationService,
            defaults: defaults,
            cooldown: 0
        )

        let event = AgentNotifyEvent(
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

        defaults.set(true, forKey: "notificationsEnabled")
        defaults.set(false, forKey: AgentNotifyEventType.taskCompleted.settingsKey)

        let notificationService = TestSocketNotifyService()
        let monitor = AgentNotifyMonitor(
            detectors: [],
            notificationService: notificationService,
            defaults: defaults,
            cooldown: 0
        )

        let event = AgentNotifyEvent(
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

        defaults.set(true, forKey: "notificationsEnabled")

        let notificationService = TestSocketNotifyService()
        let monitor = AgentNotifyMonitor(
            detectors: [],
            notificationService: notificationService,
            defaults: defaults,
            cooldown: 90
        )

        let event = AgentNotifyEvent(
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

        defaults.set(true, forKey: "notificationsEnabled")
        defaults.set(false, forKey: "notificationClaudeHookEventsEnabled")

        let notificationService = TestSocketNotifyService()
        let monitor = AgentNotifyMonitor(
            detectors: [],
            notificationService: notificationService,
            defaults: defaults,
            cooldown: 0
        )

        let event = AgentNotifyEvent(
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

    func testReceiveRespectsOpencodeSourceToggle() async throws {
        let suiteName = "AgentBarTests.MonitorReceive.OpencodeSourceToggle.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "notificationsEnabled")
        defaults.set(false, forKey: "notificationOpencodeHookEventsEnabled")

        let notificationService = TestSocketNotifyService()
        let monitor = AgentNotifyMonitor(
            detectors: [],
            notificationService: notificationService,
            defaults: defaults,
            cooldown: 0
        )

        let event = AgentNotifyEvent(
            service: .opencode,
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

        defaults.set(false, forKey: "notificationsEnabled")

        let notificationService = TestSocketNotifyService()
        let monitor = AgentNotifyMonitor(
            detectors: [],
            notificationService: notificationService,
            defaults: defaults,
            cooldown: 0
        )

        let event = AgentNotifyEvent(
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

private actor TestSocketNotifyService: AgentNotifyNotificationServiceProtocol {
    private var events: [AgentNotifyEvent] = []

    func requestAuthorizationIfNeeded() async {}

    func post(event: AgentNotifyEvent) async {
        events.append(event)
    }

    func postedEvents() -> [AgentNotifyEvent] {
        events
    }
}
