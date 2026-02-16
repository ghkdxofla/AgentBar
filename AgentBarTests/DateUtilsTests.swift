import XCTest
@testable import AgentBar

final class DateUtilsTests: XCTestCase {

    func testFiveHourWindowStart() {
        let now = Date()
        let start = DateUtils.fiveHourWindowStart(relativeTo: now)
        XCTAssertEqual(now.timeIntervalSince(start), 5 * 3600, accuracy: 0.001)
    }

    func testWeeklyWindowStart() {
        let now = Date()
        let start = DateUtils.weeklyWindowStart(relativeTo: now)
        XCTAssertEqual(now.timeIntervalSince(start), 7 * 24 * 3600, accuracy: 0.001)
    }

    func testParseISO8601WithFractionalSeconds() {
        let date = DateUtils.parseISO8601("2026-02-14T10:30:00.123Z")
        XCTAssertNotNil(date)
    }

    func testParseISO8601WithMicroseconds() {
        let date = DateUtils.parseISO8601("2025-06-05T17:12:37.153082Z")
        XCTAssertNotNil(date)
    }

    func testParseISO8601WithoutFractionalSeconds() {
        let date = DateUtils.parseISO8601("2026-02-14T10:30:00Z")
        XCTAssertNotNil(date)
    }

    func testParseISO8601Invalid() {
        let date = DateUtils.parseISO8601("not-a-date")
        XCTAssertNil(date)
    }

}
