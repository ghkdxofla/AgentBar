import SwiftUI

struct UsageHistoryTabView: View {
    @StateObject private var viewModel: UsageHistoryViewModel

    init(viewModel: UsageHistoryViewModel = UsageHistoryViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                controlsSection

                if viewModel.servicePanels.isEmpty {
                    Text("No history yet. Keep AgentBar running to collect usage.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    legend

                    ForEach(viewModel.servicePanels) { panel in
                        servicePanelSection(panel)
                    }
                }
            }
            .padding()
        }
        .onAppear {
            Task { await viewModel.refresh() }
        }
    }

    private var controlsSection: some View {
        HStack(spacing: 12) {
            Picker("Window", selection: $viewModel.selectedWindow) {
                Text("Primary").tag(UsageHistoryWindow.primary)
                Text("Secondary").tag(UsageHistoryWindow.secondary)
            }
            .pickerStyle(.segmented)

            Picker("Range", selection: $viewModel.selectedRangeWeeks) {
                Text("4w").tag(4)
                Text("8w").tag(8)
                Text("12w").tag(12)
            }
            .frame(width: 140)
        }
    }

    private func servicePanelSection(_ panel: UsageHistoryServicePanel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(panel.service.darkColor)
                    .frame(width: 8, height: 8)
                Text(panel.service.rawValue)
                    .font(.headline)
                Text(panelWindowTitle(panel))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Active days: \(panel.usageFrequencyDays)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            heatmapSection(panel)
            dailySummarySection(panel)

            if panel.isSevenDayCycleAvailable {
                cycleConsistencySection(panel)
            }

            Divider()
        }
    }

    private func heatmapSection(_ panel: UsageHistoryServicePanel) -> some View {
        let groups = groupedHeatmapCells(panel.heatmapCells)
        return HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .trailing, spacing: 3) {
                Text("Sun").font(.caption2).foregroundStyle(.secondary).frame(height: 12)
                spacerLabel
                Text("Tue").font(.caption2).foregroundStyle(.secondary).frame(height: 12)
                spacerLabel
                Text("Thu").font(.caption2).foregroundStyle(.secondary).frame(height: 12)
                spacerLabel
                Text("Sat").font(.caption2).foregroundStyle(.secondary).frame(height: 12)
            }
            .padding(.top, 1)

            HStack(alignment: .top, spacing: 3) {
                ForEach(groups.indices, id: \.self) { weekIndex in
                    VStack(spacing: 3) {
                        ForEach(groups[weekIndex]) { cell in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(tileColor(level: cell.level, service: panel.service))
                                .frame(width: 12, height: 12)
                                .help(dayTooltip(for: cell))
                        }
                    }
                }
            }
        }
    }

    private func cycleConsistencySection(_ panel: UsageHistoryServicePanel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("7d Cycle Consistency")
                .font(.subheadline.weight(.semibold))

            if panel.cycleCells.isEmpty {
                Text("Not enough 7d cycle data yet.")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 4) {
                    ForEach(panel.cycleCells) { cell in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(tileColor(level: cell.level, service: panel.service))
                            .frame(width: 16, height: 16)
                            .help(cycleTooltip(for: cell))
                    }
                }

                cycleSummarySection(panel.cycleSummary)
            }
        }
    }

    private func dailySummarySection(_ panel: UsageHistoryServicePanel) -> some View {
        HStack(spacing: 14) {
            summaryItem(title: "Limit Hit Days", value: "\(panel.dailySummary.limitHitDays)")
            summaryItem(title: "Near Limit Days", value: "\(panel.dailySummary.nearLimitDays)")
            summaryItem(
                title: "Avg Daily Peak",
                value: percentString(panel.dailySummary.averageDailyPeakRatio)
            )
            summaryItem(
                title: "Last Hit Date",
                value: panel.dailySummary.lastHitDate.map(dateString) ?? "-"
            )
        }
    }

    private func cycleSummarySection(_ summary: UsageHistoryCycleSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                summaryItem(
                    title: "Cycle Completion Rate",
                    value: percentString(summary.completionRate)
                )
                summaryItem(
                    title: "Completed Cycles",
                    value: "\(summary.completedCycles) / \(summary.totalClosedCycles)"
                )
                summaryItem(
                    title: "Avg Days to 80%",
                    value: summary.averageDaysTo80.map { formatOneDecimal($0) } ?? "-"
                )
            }

            HStack(spacing: 14) {
                summaryItem(
                    title: "Avg Days to 100%",
                    value: summary.averageDaysTo100.map { formatOneDecimal($0) } ?? "-"
                )
                summaryItem(
                    title: "Current Completion Streak",
                    value: "\(summary.currentCompletionStreak)"
                )
                summaryItem(
                    title: "Avg High-Band Hours",
                    value: formatOneDecimal(summary.averageHighBandHours)
                )
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("Less")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(tileColor(level: level, service: viewModel.servicePanels.first?.service))
                    .frame(width: 12, height: 12)
            }

            Text("More")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var spacerLabel: some View {
        Text(" ")
            .font(.caption2)
            .frame(height: 12)
    }

    private func panelWindowTitle(_ panel: UsageHistoryServicePanel) -> String {
        switch panel.displayWindow {
        case .primary:
            if viewModel.selectedWindow == .secondary && !panel.isSecondaryAvailable {
                return "\(panel.service.fiveHourLabel) (secondary unavailable)"
            }
            return panel.service.fiveHourLabel
        case .secondary:
            return panel.service.weeklyLabel
        }
    }

    private func groupedHeatmapCells(_ cells: [UsageHistoryHeatmapCell]) -> [[UsageHistoryHeatmapCell]] {
        guard !cells.isEmpty else { return [] }
        let weekCount = max(1, viewModel.selectedRangeWeeks)
        var groups: [[UsageHistoryHeatmapCell]] = Array(repeating: [], count: weekCount)

        for (index, cell) in cells.enumerated() {
            let weekIndex = min(index / 7, weekCount - 1)
            groups[weekIndex].append(cell)
        }
        return groups
    }

    private func tileColor(level: Int, service: ServiceType?) -> Color {
        let base = service?.darkColor ?? .accentColor
        switch level {
        case 0:
            return Color.gray.opacity(0.15)
        case 1:
            return base.opacity(0.25)
        case 2:
            return base.opacity(0.45)
        case 3:
            return base.opacity(0.7)
        default:
            return base.opacity(1)
        }
    }

    private func summaryItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit())
        }
    }

    private func dayTooltip(for cell: UsageHistoryHeatmapCell) -> String {
        "\(dateString(cell.date))\nPeak: \(percentString(cell.peakRatio))\nAverage: \(percentString(cell.averageRatio))\nSamples: \(cell.sampleCount)"
    }

    private func cycleTooltip(for cell: UsageHistoryCycleCell) -> String {
        let daysTo80 = cell.daysTo80.map(String.init) ?? "-"
        let daysTo100 = cell.daysTo100.map(String.init) ?? "-"
        return """
        \(dateString(cell.cycleStart)) ~ \(dateString(cell.cycleEnd))
        Peak: \(percentString(cell.peakRatio))
        Reached 80%: \(cell.reached80 ? "Yes" : "No")
        Reached 100%: \(cell.reached100 ? "Yes" : "No")
        Days to 80%: \(daysTo80)
        Days to 100%: \(daysTo100)
        High-band hours: \(formatOneDecimal(cell.highBandHours))
        """
    }

    private func percentString(_ ratio: Double) -> String {
        "\(Int((ratio * 100).rounded()))%"
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func formatOneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
