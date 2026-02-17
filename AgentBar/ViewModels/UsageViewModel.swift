import Foundation
import Combine

@MainActor
final class UsageViewModel: ObservableObject {
    @Published var usageData: [UsageData] = []
    @Published var lastError: String?
    @Published var isLoading: Bool = false

    private static let serviceOrder: [ServiceType] = [
        .claude, .codex, .gemini, .copilot, .cursor, .opencode, .zai
    ]

    private var providers: [any UsageProviderProtocol]
    private let refreshInterval: TimeInterval
    private var timerCancellable: AnyCancellable?
    private var limitsCancellable: AnyCancellable?
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
                        // Return zero usage so the bar stays visible
                        return Self.zeroUsageData(for: provider.serviceType)
                    }
                }
            }

            for await result in group {
                if let data = result {
                    results.append(data)
                }
            }
        }

        results.sort { a, b in
            Self.sortIndex(for: a.service) < Self.sortIndex(for: b.service)
        }

        usageData = results
        lastError = results.isEmpty ? "No data available" : nil
    }

    private static func sortIndex(for service: ServiceType) -> Int {
        serviceOrder.firstIndex(of: service) ?? Int.max
    }

    nonisolated private static func zeroUsageData(for service: ServiceType) -> UsageData {
        UsageData(
            service: service,
            fiveHourUsage: UsageMetric(used: 0, total: 100, unit: .percent, resetTime: nil),
            weeklyUsage: nil,
            lastUpdated: Date(),
            isAvailable: true
        )
    }

    // MARK: - Provider Factory

    private static func buildProviders() -> [any UsageProviderProtocol] {
        let defaults = UserDefaults.standard
        var providers: [any UsageProviderProtocol] = []

        if isEnabled("claudeEnabled", in: defaults) {
            providers.append(ClaudeUsageProvider())
        }

        if isEnabled("codexEnabled", in: defaults) {
            let codexLimits = codexTokenLimits(in: defaults)
            providers.append(CodexUsageProvider(
                fiveHourTokenLimit: codexLimits.fiveHour,
                weeklyTokenLimit: codexLimits.weekly
            ))
        }

        if isEnabled("geminiEnabled", in: defaults) {
            providers.append(GeminiUsageProvider(
                dailyRequestLimit: geminiDailyLimit(in: defaults)
            ))
        }

        if isEnabled("copilotEnabled", in: defaults) {
            providers.append(CopilotUsageProvider())
        }

        if isEnabled("cursorEnabled", in: defaults) {
            providers.append(CursorUsageProvider(
                monthlyRequestLimit: cursorMonthlyLimit(in: defaults)
            ))
        }

        if isEnabled("zaiEnabled", in: defaults) {
            providers.append(ZaiUsageProvider())
        }

        return providers
    }

    private static func isEnabled(_ key: String, in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: key, defaultValue: true)
    }

    private static func codexTokenLimits(in defaults: UserDefaults) -> (fiveHour: Double, weekly: Double) {
        let planRaw = defaults.string(forKey: "codexPlan") ?? CodexPlan.pro.rawValue
        let plan = CodexPlan(rawValue: planRaw) ?? .pro

        if plan == .custom {
            return (
                defaults.double(forKey: "codexFiveHourLimit").nonZero ?? CodexPlan.pro.fiveHourTokenLimit,
                defaults.double(forKey: "codexWeeklyLimit").nonZero ?? CodexPlan.pro.weeklyTokenLimit
            )
        }

        return (plan.fiveHourTokenLimit, plan.weeklyTokenLimit)
    }

    private static func geminiDailyLimit(in defaults: UserDefaults) -> Double {
        defaults.double(forKey: "geminiDailyLimit").nonZero ?? 1_000
    }

    private static func cursorMonthlyLimit(in defaults: UserDefaults) -> Double {
        let plan = CursorPlan.resolveAndMigrateStoredPlan(in: defaults)
        if plan == .custom {
            return defaults.double(forKey: "cursorMonthlyLimit").nonZero ?? CursorPlan.pro.monthlyRequestEstimate
        }
        return plan.monthlyRequestEstimate
    }
}

private extension Double {
    var nonZero: Double? {
        self > 0 ? self : nil
    }
}
