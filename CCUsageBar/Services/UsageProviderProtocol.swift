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

private final class CLIProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        let current = data
        lock.unlock()
        return current
    }
}

enum CLIProcessExecutor {
    private static let terminateGracePeriod: TimeInterval = 0.25

    static func executeCommand(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) -> String? {
        let process = Process()
        let pipe = Pipe()
        let outputHandle = pipe.fileHandleForReading
        let terminationSignal = DispatchSemaphore(value: 0)
        let outputBuffer = CLIProcessOutputBuffer()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in
            terminationSignal.signal()
        }

        outputHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            outputBuffer.append(chunk)
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
                outputHandle.readabilityHandler = nil
                let remainder = outputHandle.readDataToEndOfFile()
                outputBuffer.append(remainder)
                return outputBuffer.snapshot()
            }
        )

        defer { outputHandle.readabilityHandler = nil }
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
