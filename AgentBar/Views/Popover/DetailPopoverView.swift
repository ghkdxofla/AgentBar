import SwiftUI

struct DetailPopoverView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("AgentBar")
                    .font(.headline)
                Spacer()
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
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

            MetricRow(label: "5h", metric: data.fiveHourUsage)
            MetricRow(label: "7d", metric: data.weeklyUsage)

            if let reset = data.fiveHourUsage.resetTime {
                let remaining = reset.timeIntervalSinceNow
                if remaining > 0 {
                    Text("Reset: \(formatDuration(remaining))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
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
            Text(formatValue(metric.used, unit: metric.unit))
                .font(.caption.monospacedDigit())
            Text("/")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(formatValue(metric.total, unit: metric.unit))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(Int(metric.percentage * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(metric.percentage > 0.8 ? .red : .primary)
        }
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
                RoundedRectangle(cornerRadius: 2)
                    .fill(data.service.lightColor)
                    .frame(width: geo.size.width * data.weeklyUsage.percentage)
                RoundedRectangle(cornerRadius: 2)
                    .fill(data.service.darkColor)
                    .frame(width: geo.size.width * data.fiveHourUsage.percentage)
            }
        }
    }
}
