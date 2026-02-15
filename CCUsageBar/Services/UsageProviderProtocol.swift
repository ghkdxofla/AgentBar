import Foundation

protocol UsageProviderProtocol: Sendable {
    var serviceType: ServiceType { get }
    func isConfigured() async -> Bool
    func fetchUsage() async throws -> UsageData
}

struct CLIProcessRuntime {
    let run: () throws -> Void
    let waitForTermination: (TimeInterval) -> DispatchTimeoutResult
    let isRunning: () -> Bool
    let terminate: () -> Void
    let terminationStatus: () -> Int32
    let readOutput: () -> Data
}

enum CLIProcessExecutor {
    private static let terminateGracePeriod: TimeInterval = 0.25
    private final class LockedDataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func set(_ newData: Data) {
            lock.lock()
            data = newData
            lock.unlock()
        }

        func get() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    static func executeCommand(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) -> String? {
        let process = Process()
        let pipe = Pipe()
        let outputHandle = pipe.fileHandleForReading
        let terminationSignal = DispatchSemaphore(value: 0)
        let outputData = LockedDataBox()
        let outputReadSignal = DispatchSemaphore(value: 0)

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in
            terminationSignal.signal()
        }

        // Drain stdout while the process is running to avoid pipe backpressure deadlocks.
        DispatchQueue.global(qos: .utility).async {
            let data = outputHandle.readDataToEndOfFile()
            outputData.set(data)
            outputReadSignal.signal()
        }

        let runtime = CLIProcessRuntime(
            run: { try process.run() },
            waitForTermination: { waitTimeout in
                terminationSignal.wait(timeout: .now() + waitTimeout)
            },
            isRunning: { process.isRunning },
            terminate: { process.terminate() },
            terminationStatus: { process.terminationStatus },
            readOutput: {
                _ = outputReadSignal.wait(timeout: .distantFuture)
                return outputData.get()
            }
        )

        return executeCommand(timeout: timeout, runtime: runtime)
    }

    static func executeCommand(timeout: TimeInterval, runtime: CLIProcessRuntime) -> String? {
        do {
            try runtime.run()
        } catch {
            return nil
        }

        let waitResult = runtime.waitForTermination(timeout)
        if waitResult == .timedOut {
            if runtime.isRunning() {
                runtime.terminate()
                _ = runtime.waitForTermination(terminateGracePeriod)
            }
            return nil
        }

        guard runtime.terminationStatus() == 0 else { return nil }

        let output = String(data: runtime.readOutput(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output?.isEmpty == true ? nil : output
    }
}
