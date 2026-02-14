import SwiftUI

struct DetailPopoverView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("CCUsageBar")
                    .font(.headline)
                Spacer()
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .focusable(false)
            }

            Divider()

            if viewModel.usageData.isEmpty {
                Text("No usage data available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(viewModel.usageData) { data in
                    ServiceDetailRow(data: data)
                }
            }

            Spacer()

            // Footer
            Divider()

            HStack {
                if let error = viewModel.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Last updated: \(relativeTimeString())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 320, height: 350)
    }

    private func openSettings() {
        PopoverController.shared.hide()
        SettingsWindowController.shared.show()
    }

    private func relativeTimeString() -> String {
        guard let latest = viewModel.usageData.map(\.lastUpdated).max() else {
            return "never"
        }
        let interval = Date().timeIntervalSince(latest)
        if interval < 5 { return "just now" }
        if interval < 60 { return "\(Int(interval))s ago" }
        return "\(Int(interval / 60))m ago"
    }
}

struct ServiceDetailRow: View {
    let data: UsageData

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(data.service.darkColor)
                    .frame(width: 8, height: 8)
                Text(data.service.rawValue)
                    .font(.subheadline.weight(.medium))
                Spacer()
                MiniBarView(data: data)
                    .frame(width: 60, height: 8)
            }

            MetricRow(label: data.service.fiveHourLabel, metric: data.fiveHourUsage)
            if let weekly = data.weeklyUsage {
                MetricRow(label: data.service.weeklyLabel, metric: weekly)
            }
        }
        .padding(.vertical, 4)
    }
}

struct MetricRow: View {
    let label: String
    let metric: UsageMetric

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .leading)
            if metric.unit == .percent {
                Text(formatValue(metric.used, unit: metric.unit))
                    .font(.caption.monospacedDigit())
            } else {
                Text(formatValue(metric.used, unit: metric.unit))
                    .font(.caption.monospacedDigit())
                Text("/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatValue(metric.total, unit: metric.unit))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let reset = metric.resetTime {
                let remaining = reset.timeIntervalSinceNow
                if remaining > 0 {
                    Text(formatDuration(remaining))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
            Text("\(Int(metric.percentage * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(metric.percentage > 0.8 ? .red : .primary)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours >= 24 {
            let days = hours / 24
            let remainHours = hours % 24
            return "\(days)d \(remainHours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func formatValue(_ value: Double, unit: UsageUnit) -> String {
        switch unit {
        case .dollars:
            return String(format: "$%.2f", value)
        case .tokens:
            if value >= 1_000_000 {
                return String(format: "%.1fM", value / 1_000_000)
            } else if value >= 1_000 {
                return String(format: "%.0fK", value / 1_000)
            }
            return String(format: "%.0f", value)
        case .requests:
            return String(format: "%.0f", value)
        case .percent:
            return String(format: "%.0f%%", value)
        }
    }
}

struct MiniBarView: View {
    let data: UsageData

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.2))
                if let weekly = data.weeklyUsage, weekly.percentage > 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(data.service.lightColor)
                        .frame(width: geo.size.width * weekly.percentage)
                }
                RoundedRectangle(cornerRadius: 2)
                    .fill(data.service.darkColor)
                    .frame(width: geo.size.width * data.fiveHourUsage.percentage)
            }
        }
    }
}
