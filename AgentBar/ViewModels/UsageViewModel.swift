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
                        return UsageData(
                            service: provider.serviceType,
                            fiveHourUsage: UsageMetric(used: 0, total: 100, unit: .percent, resetTime: nil),
                            weeklyUsage: nil,
                            lastUpdated: Date(),
                            isAvailable: true
                        )
                    }
                }
            }

            for await result in group {
                if let data = result {
                    results.append(data)
                }
            }
        }

        // Sort by service order: claude, codex, gemini, copilot, cursor, opencode, zai
        let order: [ServiceType] = [.claude, .codex, .gemini, .copilot, .cursor, .opencode, .zai]
        results.sort { a, b in
            (order.firstIndex(of: a.service) ?? 0) < (order.firstIndex(of: b.service) ?? 0)
        }

        usageData = results
        lastError = results.isEmpty ? "No data available" : nil
    }

    // MARK: - Provider Factory

    private static func buildProviders() -> [any UsageProviderProtocol] {
        let defaults = UserDefaults.standard
        let claudeEnabled = defaults.bool(forKey: "claudeEnabled", defaultValue: true)
        let codexEnabled = defaults.bool(forKey: "codexEnabled", defaultValue: true)
        let geminiEnabled = defaults.bool(forKey: "geminiEnabled", defaultValue: true)
        let zaiEnabled = defaults.bool(forKey: "zaiEnabled", defaultValue: true)

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

        // Gemini request limit from AppStorage
        let geminiDailyLimit = defaults.double(forKey: "geminiDailyLimit").nonZero ?? 1_000

        var providers: [any UsageProviderProtocol] = []

        if claudeEnabled {
            providers.append(ClaudeUsageProvider())
        }

        if codexEnabled {
            providers.append(CodexUsageProvider(
                fiveHourTokenLimit: codexFiveHour,
                weeklyTokenLimit: codexWeekly
            ))
        }

        if geminiEnabled {
            providers.append(GeminiUsageProvider(
                dailyRequestLimit: geminiDailyLimit
            ))
        }

        let copilotEnabled = defaults.bool(forKey: "copilotEnabled", defaultValue: true)
        if copilotEnabled {
            providers.append(CopilotUsageProvider())
        }

        let cursorEnabled = defaults.bool(forKey: "cursorEnabled", defaultValue: true)
        if cursorEnabled {
            let cursorPlan = CursorPlan.resolveAndMigrateStoredPlan(in: defaults)
            let cursorLimit: Double
            if cursorPlan == .custom {
                cursorLimit = defaults.double(forKey: "cursorMonthlyLimit").nonZero ?? CursorPlan.pro.monthlyRequestEstimate
            } else {
                cursorLimit = cursorPlan.monthlyRequestEstimate
            }
            providers.append(CursorUsageProvider(monthlyRequestLimit: cursorLimit))
        }

        if zaiEnabled {
            providers.append(ZaiUsageProvider())
        }

        return providers
    }
}

private extension Double {
    var nonZero: Double? {
        self > 0 ? self : nil
    }
}
