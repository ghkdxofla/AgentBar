import XCTest
@testable import AgentBar

final class DateUtilsTests: XCTestCase {

    func testFiveHourWindowBoundary() {
        let now = Date()
        let fiveHoursAgo = now.addingTimeInterval(-5 * 3600)
        let justInside = now.addingTimeInterval(-4 * 3600 - 59 * 60)
        let justOutside = now.addingTimeInterval(-5 * 3600 - 1)

        XCTAssertTrue(DateUtils.isWithinFiveHourWindow(justInside, relativeTo: now))
        XCTAssertTrue(DateUtils.isWithinFiveHourWindow(fiveHoursAgo, relativeTo: now))
        XCTAssertFalse(DateUtils.isWithinFiveHourWindow(justOutside, relativeTo: now))
    }

    func testWeeklyWindowBoundary() {
        let now = Date()
        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 3600)
        let justOutside = now.addingTimeInterval(-7 * 24 * 3600 - 1)

        XCTAssertTrue(DateUtils.isWithinWeeklyWindow(sevenDaysAgo, relativeTo: now))
        XCTAssertFalse(DateUtils.isWithinWeeklyWindow(justOutside, relativeTo: now))
    }

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

    func testNextResetTime() {
        let now = Date()
        let resetTime = DateUtils.nextResetTime(from: now, windowDuration: 5 * 3600)
        let diff = resetTime.timeIntervalSince(now)
        XCTAssertEqual(diff, 5 * 3600, accuracy: 0.001)
    }

    func testNextResetAlignedUsesAnchorAndWindow() {
        let anchor = DateUtils.parseISO8601("2026-02-14T03:03:35.530Z")!
        let now = DateUtils.parseISO8601("2026-02-14T12:54:00Z")!

        let reset = DateUtils.nextResetAligned(
            to: anchor,
            windowDuration: DateUtils.fiveHourInterval,
            relativeTo: now
        )

        // 5h windows from 03:03:35 are 08:03:35, 13:03:35, ...
        let expected = DateUtils.parseISO8601("2026-02-14T13:03:35.530Z")!
        XCTAssertEqual(reset.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001)
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

    func testCurrentTimeIsWithinFiveHourWindow() {
        let now = Date()
        XCTAssertTrue(DateUtils.isWithinFiveHourWindow(now, relativeTo: now))
    }

    func testFutureTimeIsNotInWindow() {
        let now = Date()
        let future = now.addingTimeInterval(100)
        XCTAssertFalse(DateUtils.isWithinFiveHourWindow(future, relativeTo: now))
    }
}
