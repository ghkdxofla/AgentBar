import Foundation
import Combine

@MainActor
final class UsageViewModel: ObservableObject {
    @Published var usageData: [UsageData] = []
    @Published var lastError: String?
    @Published var isLoading: Bool = false

    private let providers: [any UsageProviderProtocol]
    private let refreshInterval: TimeInterval
    private var timerCancellable: AnyCancellable?
    private var consecutiveFailures: [ServiceType: Int] = [:]

    init(
        providers: [any UsageProviderProtocol]? = nil,
        refreshInterval: TimeInterval = 60
    ) {
        self.providers = providers ?? [
            ClaudeUsageProvider(),
            CodexUsageProvider(),
            ZaiUsageProvider()
        ]
        self.refreshInterval = refreshInterval
    }

    func startMonitoring() {
        // Initial fetch
        Task { await fetchAllUsage() }

        // Periodic refresh
        timerCancellable = Timer.publish(every: refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.fetchAllUsage()
                }
            }
    }

    func stopMonitoring() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    func fetchAllUsage() async {
        isLoading = true
        defer { isLoading = false }

        var results: [UsageData] = []

        await withTaskGroup(of: UsageData?.self) { group in
            for provider in providers {
                group.addTask {
                    guard await provider.isConfigured() else { return nil }
                    do {
                        return try await provider.fetchUsage()
                    } catch {
                        return nil
                    }
                }
            }

            for await result in group {
                if let data = result {
                    results.append(data)
                }
            }
        }

        // Sort by service order: claude, codex, zai
        let order: [ServiceType] = [.claude, .codex, .zai]
        results.sort { a, b in
            (order.firstIndex(of: a.service) ?? 0) < (order.firstIndex(of: b.service) ?? 0)
        }

        usageData = results
        lastError = results.isEmpty ? "No data available" : nil
    }
}
