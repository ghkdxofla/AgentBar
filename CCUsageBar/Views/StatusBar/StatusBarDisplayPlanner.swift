import Foundation
import CoreGraphics

struct StatusBarDisplayPage: Sendable {
    let id: String
    let services: [UsageData]
    let isTopPriority: Bool
}

enum StatusBarDisplayPlanner {
    static let topPriorityCount = 3
    static let topPriorityHoldSeconds: TimeInterval = 8
    static let overflowHoldSeconds: TimeInterval = 5
    static let transitionSeconds: TimeInterval = 1.2
    static let pageHeight: CGFloat = 20

    private static let serviceOrder: [ServiceType] = [.claude, .codex, .gemini, .copilot, .cursor, .zai]

    static func pages(from services: [UsageData]) -> [StatusBarDisplayPage] {
        let ranked = rankedServices(from: services)
        guard !ranked.isEmpty else { return [] }

        let top = Array(ranked.prefix(topPriorityCount))
        guard ranked.count > topPriorityCount else {
            return [makePage(services: top, isTopPriority: true, index: 0)]
        }

        let overflow = Array(ranked.dropFirst(topPriorityCount))
        let overflowChunks = chunk(overflow, size: topPriorityCount)

        var pages: [StatusBarDisplayPage] = [
            makePage(services: top, isTopPriority: true, index: 0)
        ]

        for (offset, chunk) in overflowChunks.enumerated() {
            pages.append(makePage(services: chunk, isTopPriority: false, index: offset + 1))
            pages.append(makePage(services: top, isTopPriority: true, index: offset + 1))
        }

        return pages
    }

    static func rankedServices(from services: [UsageData]) -> [UsageData] {
        services
            .filter(\.isAvailable)
            .sorted { lhs, rhs in
                let lhsScore = usageScore(lhs)
                let rhsScore = usageScore(rhs)
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }

                let lhsRank = serviceOrder.firstIndex(of: lhs.service) ?? serviceOrder.count
                let rhsRank = serviceOrder.firstIndex(of: rhs.service) ?? serviceOrder.count
                return lhsRank < rhsRank
            }
    }

    static func displayDuration(for page: StatusBarDisplayPage) -> TimeInterval {
        page.isTopPriority ? topPriorityHoldSeconds : overflowHoldSeconds
    }

    private static func usageScore(_ data: UsageData) -> Double {
        let weekly = data.weeklyUsage?.percentage ?? 0
        return max(data.fiveHourUsage.percentage, weekly)
    }

    private static func chunk(_ items: [UsageData], size: Int) -> [[UsageData]] {
        guard size > 0 else { return [items] }
        var result: [[UsageData]] = []
        var index = 0
        while index < items.count {
            let end = min(index + size, items.count)
            result.append(Array(items[index..<end]))
            index = end
        }
        return result
    }

    private static func makePage(services: [UsageData], isTopPriority: Bool, index: Int) -> StatusBarDisplayPage {
        let serviceIDs = services.map { $0.service.rawValue.replacingOccurrences(of: " ", with: "_") }.joined(separator: ",")
        return StatusBarDisplayPage(
            id: "\(isTopPriority ? "top" : "overflow")-\(index)-\(serviceIDs)",
            services: services,
            isTopPriority: isTopPriority
        )
    }
}
