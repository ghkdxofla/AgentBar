import Foundation
import Combine

@MainActor
final class UsageViewModel: ObservableObject {
    @Published var usageData: [UsageData] = []
    @Published var lastError: String?
    @Published var isLoading: Bool = false

    private var providers: [any UsageProviderProtocol]
    private let refreshInterval: TimeInterval
    private var timerCancellable: AnyCancellable?
    private var limitsCancellable: AnyCancellable?
    private var consecutiveFailures: [ServiceType: Int] = [:]

    init(
        providers: [any UsageProviderProtocol]? = nil,
        refreshInterval: TimeInterval = 60
    ) {
        self.refreshInterval = refreshInterval
        self.providers = providers ?? Self.buildProviders()

        if providers == nil {
            limitsCancellable = NotificationCenter.default
                .publisher(for: .limitsChanged)
                .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
                .sink { [weak self] _ in
                    self?.rebuildProviders()
                }
        }
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

    func rebuildProviders() {
        providers = Self.buildProviders()
        Task { await fetchAllUsage() }
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

    // MARK: - Provider Factory

    private static func buildProviders() -> [any UsageProviderProtocol] {
        let defaults = UserDefaults.standard

        // Claude limits from AppStorage
        let claudePlanRaw = defaults.string(forKey: "claudePlan") ?? ClaudePlan.max5x.rawValue
        let claudePlan = ClaudePlan(rawValue: claudePlanRaw) ?? .max5x
        let claudeFiveHour: Double
        let claudeWeekly: Double
        if claudePlan == .custom {
            claudeFiveHour = defaults.double(forKey: "claudeFiveHourLimit").nonZero ?? ClaudePlan.max5x.fiveHourTokenLimit
            claudeWeekly = defaults.double(forKey: "claudeWeeklyLimit").nonZero ?? ClaudePlan.max5x.weeklyTokenLimit
        } else {
            claudeFiveHour = claudePlan.fiveHourTokenLimit
            claudeWeekly = claudePlan.weeklyTokenLimit
        }

        // Codex limits from AppStorage
        let codexPlanRaw = defaults.string(forKey: "codexPlan") ?? CodexPlan.pro.rawValue
        let codexPlan = CodexPlan(rawValue: codexPlanRaw) ?? .pro
        let codexFiveHour: Double
        let codexWeekly: Double
        if codexPlan == .custom {
            codexFiveHour = defaults.double(forKey: "codexFiveHourLimit").nonZero ?? CodexPlan.pro.fiveHourTokenLimit
            codexWeekly = defaults.double(forKey: "codexWeeklyLimit").nonZero ?? CodexPlan.pro.weeklyTokenLimit
        } else {
            codexFiveHour = codexPlan.fiveHourTokenLimit
            codexWeekly = codexPlan.weeklyTokenLimit
        }

        return [
            ClaudeUsageProvider(
                fiveHourTokenLimit: claudeFiveHour,
                weeklyTokenLimit: claudeWeekly
            ),
            CodexUsageProvider(
                fiveHourTokenLimit: codexFiveHour,
                weeklyTokenLimit: codexWeekly
            ),
            ZaiUsageProvider()
        ]
    }
}

private extension Double {
    var nonZero: Double? {
        self > 0 ? self : nil
    }
}
