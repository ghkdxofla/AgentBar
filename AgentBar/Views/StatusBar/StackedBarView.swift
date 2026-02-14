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
            .frame(width: 64, height: 20)
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

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.gray.opacity(0.2))

                // Weekly usage (light color)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(usage.service.lightColor)
                    .frame(width: geo.size.width * usage.weeklyUsage.percentage)

                // 5-hour usage (dark color, overlaps weekly)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(usage.service.darkColor)
                    .frame(width: geo.size.width * usage.fiveHourUsage.percentage)
            }
        }
        .frame(height: barHeight)
    }
}
