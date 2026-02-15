import XCTest
@testable import CCUsageBar

final class StatusBarDisplayPlannerTests: XCTestCase {
    func testRanksServicesByHighestUsageScoreDescending() {
        let services = [
            makeUsage(service: .claude, fiveHourPct: 0.20, weeklyPct: 0.40),
            makeUsage(service: .codex, fiveHourPct: 0.90, weeklyPct: 0.10),
            makeUsage(service: .gemini, fiveHourPct: 0.50, weeklyPct: 0.60)
        ]

        let ranked = StatusBarDisplayPlanner.rankedServices(from: services)
        XCTAssertEqual(ranked.map(\.service), [.codex, .gemini, .claude])
    }

    func testReturnsSingleTopPageWhenThreeOrFewerServices() {
        let services = [
            makeUsage(service: .claude, fiveHourPct: 0.8),
            makeUsage(service: .codex, fiveHourPct: 0.7),
            makeUsage(service: .gemini, fiveHourPct: 0.6)
        ]

        let pages = StatusBarDisplayPlanner.pages(from: services)
        XCTAssertEqual(pages.count, 1)
        XCTAssertTrue(pages[0].isTopPriority)
        XCTAssertEqual(pages[0].services.map(\.service), [.claude, .codex, .gemini])
    }

    func testInterleavesTopPageBetweenOverflowPages() {
        let services = [
            makeUsage(service: .claude, fiveHourPct: 0.95),
            makeUsage(service: .codex, fiveHourPct: 0.90),
            makeUsage(service: .gemini, fiveHourPct: 0.85),
            makeUsage(service: .copilot, fiveHourPct: 0.80),
            makeUsage(service: .cursor, fiveHourPct: 0.75),
            makeUsage(service: .zai, fiveHourPct: 0.70),
            makeUsage(service: .claude, fiveHourPct: 0.65, available: false) // ignored
        ]

        let pages = StatusBarDisplayPlanner.pages(from: services)
        XCTAssertEqual(pages.count, 3)

        XCTAssertEqual(pages[0].services.map(\.service), [.claude, .codex, .gemini])
        XCTAssertTrue(pages[0].isTopPriority)

        XCTAssertEqual(pages[1].services.map(\.service), [.copilot, .cursor, .zai])
        XCTAssertFalse(pages[1].isTopPriority)

        XCTAssertEqual(pages[2].services.map(\.service), [.claude, .codex, .gemini])
        XCTAssertTrue(pages[2].isTopPriority)
    }

    func testOverflowWithMoreThanOneChunkKeepsReturningToTopPage() {
        let services = [
            makeUsage(service: .claude, fiveHourPct: 0.99),
            makeUsage(service: .codex, fiveHourPct: 0.98),
            makeUsage(service: .gemini, fiveHourPct: 0.97),
            makeUsage(service: .copilot, fiveHourPct: 0.96),
            makeUsage(service: .cursor, fiveHourPct: 0.95),
            makeUsage(service: .zai, fiveHourPct: 0.94),
            makeUsage(service: .claude, fiveHourPct: 0.93), // duplicate service type acceptable in test fixture
            makeUsage(service: .codex, fiveHourPct: 0.92)
        ]

        let pages = StatusBarDisplayPlanner.pages(from: services)

        XCTAssertEqual(pages.count, 5)
        XCTAssertTrue(pages[0].isTopPriority)
        XCTAssertFalse(pages[1].isTopPriority)
        XCTAssertTrue(pages[2].isTopPriority)
        XCTAssertFalse(pages[3].isTopPriority)
        XCTAssertTrue(pages[4].isTopPriority)
    }

    func testDisplayDurationPrioritizesTopPage() {
        let topPage = StatusBarDisplayPage(id: "top", services: [makeUsage(service: .claude, fiveHourPct: 0.9)], isTopPriority: true)
        let overflowPage = StatusBarDisplayPage(id: "overflow", services: [makeUsage(service: .codex, fiveHourPct: 0.5)], isTopPriority: false)

        XCTAssertEqual(StatusBarDisplayPlanner.displayDuration(for: topPage), StatusBarDisplayPlanner.topPriorityHoldSeconds)
        XCTAssertEqual(StatusBarDisplayPlanner.displayDuration(for: overflowPage), StatusBarDisplayPlanner.overflowHoldSeconds)
    }

    private func makeUsage(
        service: ServiceType,
        fiveHourPct: Double,
        weeklyPct: Double = 0,
        available: Bool = true
    ) -> UsageData {
        UsageData(
            service: service,
            fiveHourUsage: UsageMetric(
                used: fiveHourPct * 100,
                total: 100,
                unit: .percent,
                resetTime: nil
            ),
            weeklyUsage: UsageMetric(
                used: weeklyPct * 100,
                total: 100,
                unit: .percent,
                resetTime: nil
            ),
            lastUpdated: Date(),
            isAvailable: available
        )
    }
}
