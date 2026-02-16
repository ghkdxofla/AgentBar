import Foundation
import Network

struct SocketAlertEvent: Decodable, Sendable {
    let agent: String
    let event: String
    let sessionID: String?
    let message: String?
    let timestamp: String?

    enum CodingKeys: String, CodingKey {
        case agent, event, message, timestamp
        case sessionID = "session_id"
    }
}

final class AlertSocketListener: @unchecked Sendable {
    private let socketPath: String
    private let fileManager: FileManager
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "com.agentbar.socket-listener")
    var onEvent: (@Sendable (AgentAlertEvent) -> Void)?

    private(set) var isListening = false

    init(
        socketPath: String? = nil,
        fileManager: FileManager = .default
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.socketPath = socketPath ?? "\(home)/.agentbar/events.sock"
        self.fileManager = fileManager
    }

    func start() {
        cleanupStaleSocket()

        let dir = (socketPath as NSString).deletingLastPathComponent
        try? fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let endpoint = NWEndpoint.unix(path: socketPath)
        let params = NWParameters()
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        params.requiredLocalEndpoint = endpoint

        do {
            let nwListener = try NWListener(using: params)
            self.listener = nwListener

            nwListener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.isListening = true
                case .failed, .cancelled:
                    self?.isListening = false
                default:
                    break
                }
            }

            nwListener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            nwListener.start(queue: queue)
        } catch {
            isListening = false
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()
        isListening = false
        cleanupStaleSocket()
    }

    private func cleanupStaleSocket() {
        if fileManager.fileExists(atPath: socketPath) {
            try? fileManager.removeItem(atPath: socketPath)
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connections.append(connection)

        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state {
                self?.queue.async { [weak self] in
                    self?.connections.removeAll { $0 === connection }
                }
            }
        }

        connection.start(queue: queue)
        receiveData(on: connection, buffer: Data())
    }

    private func receiveData(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }

            var accumulated = buffer
            if let content {
                accumulated.append(content)
            }

            if isComplete || error != nil {
                self.processBuffer(accumulated)
                connection.cancel()
                return
            }

            self.receiveData(on: connection, buffer: accumulated)
        }
    }

    private func processBuffer(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }

        let lines = text.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            guard let jsonData = trimmed.data(using: .utf8),
                  let socketEvent = try? JSONDecoder().decode(SocketAlertEvent.self, from: jsonData) else {
                continue
            }

            guard let alertEvent = mapSocketEvent(socketEvent) else { continue }
            onEvent?(alertEvent)
        }
    }

    static func mapEventType(_ event: String) -> AgentAlertEventType? {
        switch event.lowercased() {
        case "stop", "subagent_stop":
            return .taskCompleted
        case "permission":
            return .permissionRequired
        case "decision":
            return .decisionRequired
        default:
            return nil
        }
    }

    static func mapAgent(_ agent: String) -> ServiceType? {
        switch agent.lowercased() {
        case "claude":
            return .claude
        case "codex":
            return .codex
        case "gemini":
            return .gemini
        case "copilot":
            return .copilot
        case "cursor":
            return .cursor
        case "zai":
            return .zai
        default:
            return nil
        }
    }

    private func mapSocketEvent(_ socketEvent: SocketAlertEvent) -> AgentAlertEvent? {
        guard let service = Self.mapAgent(socketEvent.agent),
              let eventType = Self.mapEventType(socketEvent.event) else {
            return nil
        }

        let timestamp: Date
        if let ts = socketEvent.timestamp, let parsed = DateUtils.parseISO8601(ts) {
            timestamp = parsed
        } else {
            timestamp = Date()
        }

        return AgentAlertEvent(
            service: service,
            type: eventType,
            timestamp: timestamp,
            message: socketEvent.message,
            sessionID: socketEvent.sessionID,
            sourceRecordID: "socket-\(UUID().uuidString)"
        )
    }
}
