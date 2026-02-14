import Foundation
@testable import AgentBar

final class MockUsageProvider: UsageProviderProtocol, @unchecked Sendable {
    let serviceType: ServiceType
    let result: Result<UsageData, Error>
    let delay: TimeInterval
    var fetchCount = 0

    init(serviceType: ServiceType, result: Result<UsageData, Error>, delay: TimeInterval = 0) {
        self.serviceType = serviceType
        self.result = result
        self.delay = delay
    }

    func isConfigured() async -> Bool { true }

    func fetchUsage() async throws -> UsageData {
        fetchCount += 1
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        return try result.get()
    }
}

extension UsageData {
    static func mock(
        service: ServiceType,
        fiveHourPct: Double = 0.5,
        weeklyPct: Double = 0.7
    ) -> UsageData {
        UsageData(
            service: service,
            fiveHourUsage: UsageMetric(
                used: fiveHourPct * 1_000_000,
                total: 1_000_000,
                unit: .tokens,
                resetTime: Date().addingTimeInterval(3600)
            ),
            weeklyUsage: UsageMetric(
                used: weeklyPct * 10_000_000,
                total: 10_000_000,
                unit: .tokens,
                resetTime: Date().addingTimeInterval(7 * 24 * 3600)
            ),
            lastUpdated: Date(),
            isAvailable: true
        )
    }
}
