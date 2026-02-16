import Foundation

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
    private let queue = DispatchQueue(label: "com.agentbar.socket-listener")
    var onEvent: (@Sendable (AgentAlertEvent) -> Void)?

    private var serverFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var _isListening = false

    var isListening: Bool {
        queue.sync { _isListening }
    }

    init(
        socketPath: String? = nil,
        fileManager: FileManager = .default
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.socketPath = socketPath ?? "\(home)/.agentbar/events.sock"
        self.fileManager = fileManager
    }

    func start() {
        queue.sync { self._start() }
    }

    func stop() {
        queue.sync { self._stop() }
    }

    private func _start() {
        _stop()

        let dir = (socketPath as NSString).deletingLastPathComponent
        try? fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: socketPath) {
            try? fileManager.removeItem(atPath: socketPath)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            return
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                for (i, byte) in pathBytes.enumerated() {
                    dest[i] = byte
                }
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, addrLen)
            }
        }
        guard bindResult == 0 else {
            close(fd)
            return
        }

        guard listen(fd, 5) == 0 else {
            close(fd)
            try? fileManager.removeItem(atPath: socketPath)
            return
        }

        // Set non-blocking
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        serverFD = fd
        _isListening = true

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.serverFD >= 0 {
                close(self.serverFD)
                self.serverFD = -1
            }
            try? self.fileManager.removeItem(atPath: self.socketPath)
            self._isListening = false
        }
        self.acceptSource = source
        source.resume()
    }

    private func _stop() {
        if let source = acceptSource {
            source.cancel()
            acceptSource = nil
        } else if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
            if fileManager.fileExists(atPath: socketPath) {
                try? fileManager.removeItem(atPath: socketPath)
            }
            _isListening = false
        }
    }

    private func acceptConnection() {
        let clientFD = accept(serverFD, nil, nil)
        guard clientFD >= 0 else { return }

        let flags = fcntl(clientFD, F_GETFL)
        _ = fcntl(clientFD, F_SETFL, flags | O_NONBLOCK)

        var buffer = Data()
        let readSource = DispatchSource.makeReadSource(fileDescriptor: clientFD, queue: queue)
        readSource.setEventHandler { [weak self] in
            var buf = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(clientFD, &buf, buf.count)
            if bytesRead > 0 {
                buffer.append(contentsOf: buf[0..<bytesRead])
            } else {
                // EOF or error: process and close
                readSource.cancel()
                self?.processBuffer(buffer)
                close(clientFD)
            }
        }
        readSource.setCancelHandler {
            // Ensure close on cancel
        }
        readSource.resume()
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
