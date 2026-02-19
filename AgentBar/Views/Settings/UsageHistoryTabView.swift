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

                if viewModel.availableServices.isEmpty {
                    Text("No history yet. Keep AgentBar running to collect usage.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    dailyHeatmapSection

                    if viewModel.isSevenDayCycleAvailable {
                        cycleConsistencySection
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Picker("Service", selection: $viewModel.selectedService) {
                    ForEach(viewModel.availableServices, id: \.self) { service in
                        Text(service.rawValue).tag(Optional(service))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Picker("Range", selection: $viewModel.selectedRangeWeeks) {
                    Text("4w").tag(4)
                    Text("8w").tag(8)
                    Text("12w").tag(12)
                }
                .frame(width: 140)
            }

            if let selectedService = viewModel.selectedService {
                Picker("Window", selection: $viewModel.selectedWindow) {
                    Text(selectedService.fiveHourLabel).tag(UsageHistoryWindow.primary)
                    Text(selectedService.weeklyLabel).tag(UsageHistoryWindow.secondary)
                }
                .pickerStyle(.segmented)
                .disabled(!viewModel.isSecondaryAvailable)
            }
        }
    }

    private var dailyHeatmapSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily Heatmap")
                .font(.headline)

            HStack(alignment: .top, spacing: 6) {
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
                    ForEach(groupedHeatmapCells.indices, id: \.self) { weekIndex in
                        VStack(spacing: 3) {
                            ForEach(groupedHeatmapCells[weekIndex]) { cell in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(tileColor(level: cell.level))
                                    .frame(width: 12, height: 12)
                                    .help(dayTooltip(for: cell))
                            }
                        }
                    }
                }
            }

            dailySummarySection
            legend
        }
    }

    private var cycleConsistencySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("7d Cycle Consistency")
                .font(.headline)

            if viewModel.cycleCells.isEmpty {
                Text("Not enough 7d cycle data yet.")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 4) {
                    ForEach(viewModel.cycleCells) { cell in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(tileColor(level: cell.level))
                            .frame(width: 16, height: 16)
                            .help(cycleTooltip(for: cell))
                    }
                }

                cycleSummarySection
            }
        }
    }

    private var dailySummarySection: some View {
        HStack(spacing: 14) {
            summaryItem(
                title: "Limit Hit Days",
                value: "\(viewModel.dailySummary.limitHitDays)"
            )
            summaryItem(
                title: "Near Limit Days",
                value: "\(viewModel.dailySummary.nearLimitDays)"
            )
            summaryItem(
                title: "Avg Daily Peak",
                value: percentString(viewModel.dailySummary.averageDailyPeakRatio)
            )
            summaryItem(
                title: "Last Hit Date",
                value: viewModel.dailySummary.lastHitDate.map(dateString) ?? "-"
            )
        }
    }

    private var cycleSummarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                summaryItem(
                    title: "Cycle Completion Rate",
                    value: percentString(viewModel.cycleSummary.completionRate)
                )
                summaryItem(
                    title: "Completed Cycles",
                    value: "\(viewModel.cycleSummary.completedCycles) / \(viewModel.cycleSummary.totalClosedCycles)"
                )
                summaryItem(
                    title: "Avg Days to 80%",
                    value: viewModel.cycleSummary.averageDaysTo80.map { formatOneDecimal($0) } ?? "-"
                )
            }

            HStack(spacing: 14) {
                summaryItem(
                    title: "Avg Days to 100%",
                    value: viewModel.cycleSummary.averageDaysTo100.map { formatOneDecimal($0) } ?? "-"
                )
                summaryItem(
                    title: "Current Completion Streak",
                    value: "\(viewModel.cycleSummary.currentCompletionStreak)"
                )
                summaryItem(
                    title: "Avg High-Band Hours",
                    value: formatOneDecimal(viewModel.cycleSummary.averageHighBandHours)
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
                    .fill(tileColor(level: level))
                    .frame(width: 12, height: 12)
            }

            Text("More")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var groupedHeatmapCells: [[UsageHistoryHeatmapCell]] {
        guard !viewModel.heatmapCells.isEmpty else { return [] }
        let weekCount = max(1, viewModel.selectedRangeWeeks)
        var groups: [[UsageHistoryHeatmapCell]] = Array(repeating: [], count: weekCount)

        for (index, cell) in viewModel.heatmapCells.enumerated() {
            let weekIndex = min(index / 7, weekCount - 1)
            groups[weekIndex].append(cell)
        }
        return groups
    }

    private var spacerLabel: some View {
        Text(" ")
            .font(.caption2)
            .frame(height: 12)
    }

    private func tileColor(level: Int) -> Color {
        let base = viewModel.selectedService?.darkColor ?? .accentColor
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
