import Foundation

enum DateUtils {
    static let fiveHourInterval: TimeInterval = 5 * 3600
    static let weeklyInterval: TimeInterval = 7 * 24 * 3600

    static func isWithinFiveHourWindow(_ date: Date, relativeTo now: Date = Date()) -> Bool {
        let boundary = now.addingTimeInterval(-fiveHourInterval)
        return date >= boundary && date <= now
    }

    static func isWithinWeeklyWindow(_ date: Date, relativeTo now: Date = Date()) -> Bool {
        let boundary = now.addingTimeInterval(-weeklyInterval)
        return date >= boundary && date <= now
    }

    static func fiveHourWindowStart(relativeTo now: Date = Date()) -> Date {
        now.addingTimeInterval(-fiveHourInterval)
    }

    static func weeklyWindowStart(relativeTo now: Date = Date()) -> Date {
        now.addingTimeInterval(-weeklyInterval)
    }

    static func nextResetTime(from date: Date, windowDuration: TimeInterval) -> Date {
        date.addingTimeInterval(windowDuration)
    }

    static func parseISO8601(_ string: String) -> Date? {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFrac.date(from: string) { return date }

        let noFrac = ISO8601DateFormatter()
        noFrac.formatOptions = [.withInternetDateTime]
        return noFrac.date(from: string)
    }
}
