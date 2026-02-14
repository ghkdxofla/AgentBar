import SwiftUI

struct StackedBarView: View {
    let services: [UsageData]
    var hasError: Bool = false

    private var activeServices: [UsageData] {
        services.filter(\.isAvailable)
    }

    var body: some View {
        if activeServices.isEmpty {
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
            VStack(spacing: 1) {
                ForEach(activeServices) { data in
                    SingleBarView(usage: data, serviceCount: activeServices.count)
                }
            }
            .frame(height: 20)
            .padding(.horizontal, 2)
        }
    }
}

struct SingleBarView: View {
    let usage: UsageData
    let serviceCount: Int

    private var barHeight: CGFloat {
        switch serviceCount {
        case 1: 12
        case 2: 8
        default: 5
        }
    }

    private var fontSize: CGFloat {
        switch serviceCount {
        case 1: 8
        case 2: 7
        default: 6
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
                    if usage.weeklyUsage.percentage > 0 {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(usage.service.lightColor)
                            .frame(width: max(2, geo.size.width * usage.weeklyUsage.percentage))
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
