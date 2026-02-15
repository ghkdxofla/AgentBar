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

    static func nextResetAligned(
        to anchor: Date,
        windowDuration: TimeInterval,
        relativeTo now: Date = Date()
    ) -> Date {
        guard windowDuration > 0 else { return now }

        let elapsed = now.timeIntervalSince(anchor)
        guard elapsed > 0 else { return anchor }

        let completedWindows = floor(elapsed / windowDuration)
        let nextWindowIndex = completedWindows + 1
        return anchor.addingTimeInterval(nextWindowIndex * windowDuration)
    }

    static func parseISO8601(_ string: String) -> Date? {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFrac.date(from: string) { return date }

        let noFrac = ISO8601DateFormatter()
        noFrac.formatOptions = [.withInternetDateTime]
        if let date = noFrac.date(from: string) { return date }

        // Handles timestamps like "2025-06-05T17:12:37.153082Z" from ~/.claude.json
        let microsecondFormatter = DateFormatter()
        microsecondFormatter.locale = Locale(identifier: "en_US_POSIX")
        microsecondFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        microsecondFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
        return microsecondFormatter.date(from: string)
    }
}
