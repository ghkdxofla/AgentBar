import SwiftUI

struct StackedBarView: View {
    let services: [UsageData]
    var hasError: Bool = false

    @State private var currentPageIndex = 0

    private var pages: [StatusBarDisplayPage] {
        StatusBarDisplayPlanner.pages(from: services)
    }

    private var cycleTaskID: String {
        pages.map(\.id).joined(separator: "|")
    }

    var body: some View {
        if pages.isEmpty {
            HStack(spacing: 2) {
                if hasError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                } else {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 24, height: 20)
        } else {
            scrollingPages
                .task(id: cycleTaskID) {
                    await startCycleIfNeeded()
                }
            .padding(.horizontal, 2)
        }
    }

    private var scrollingPages: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                ForEach(pages, id: \.id) { page in
                    StatusBarPageView(services: page.services)
                        .frame(height: StatusBarDisplayPlanner.pageHeight)
                }
            }
            .offset(y: -CGFloat(currentPageIndex) * StatusBarDisplayPlanner.pageHeight)
            .animation(
                .easeInOut(duration: StatusBarDisplayPlanner.transitionSeconds),
                value: currentPageIndex
            )
        }
        .frame(height: StatusBarDisplayPlanner.pageHeight)
        .clipped()
    }

    @MainActor
    private func startCycleIfNeeded() async {
        currentPageIndex = 0
        guard pages.count > 1 else { return }

        while !Task.isCancelled {
            let currentPage = pages[currentPageIndex]
            let duration = StatusBarDisplayPlanner.displayDuration(for: currentPage)
            let nanoseconds = UInt64(duration * 1_000_000_000)

            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: StatusBarDisplayPlanner.transitionSeconds)) {
                currentPageIndex = (currentPageIndex + 1) % pages.count
            }
        }
    }
}

private struct StatusBarPageView: View {
    let services: [UsageData]

    var body: some View {
        VStack(spacing: 1) {
            ForEach(services) { data in
                SingleBarView(usage: data, serviceCount: services.count)
            }
        }
        .frame(height: StatusBarDisplayPlanner.pageHeight)
    }
}

struct SingleBarView: View {
    let usage: UsageData
    let serviceCount: Int

    private var barHeight: CGFloat {
        switch serviceCount {
        case 1: return 12
        case 2: return 8
        case 3: return 5
        case 4: return 4
        default:
            let spacing = CGFloat(max(serviceCount - 1, 0))
            let available = 20 - spacing
            return max(3, floor(available / CGFloat(max(serviceCount, 1))))
        }
    }

    private var fontSize: CGFloat {
        switch serviceCount {
        case 1: return 8
        case 2: return 7
        case 3: return 6
        case 4: return 5.5
        default: return 5
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Text(usage.service.shortName)
                .font(.system(size: fontSize, weight: .medium, design: .rounded))
                .foregroundStyle(usage.service.darkColor)
                .frame(width: 14, alignment: .trailing)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background — visible outline when empty
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(usage.service.darkColor.opacity(0.15))

                    // Weekly usage (light color)
                    if let weekly = usage.weeklyUsage, weekly.percentage > 0 {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(usage.service.lightColor)
                            .frame(width: max(2, geo.size.width * weekly.percentage))
                    }

                    // 5-hour usage (dark color, overlaps weekly)
                    if usage.fiveHourUsage.percentage > 0 {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(usage.service.darkColor)
                            .frame(width: max(2, geo.size.width * usage.fiveHourUsage.percentage))
                    }
                }
            }
        }
        .frame(height: barHeight)
    }
}
