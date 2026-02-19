import XCTest
@testable import AgentBar

final class UsageHistoryTabViewTests: XCTestCase {
    func testShowsWeekdayAxisOnlyForPrimaryWindow() {
        XCTAssertTrue(UsageHistoryTabView.showsWeekdayAxis(for: .primary))
        XCTAssertFalse(UsageHistoryTabView.showsWeekdayAxis(for: .secondary))
    }
}
