import Foundation

protocol UsageHistoryStoreProtocol: Sendable {
    func record(samples: [UsageData], recordedAt: Date) async
    func dayRecords(for service: ServiceType, since: Date, until: Date) async -> [UsageHistoryDayRecord]
    func secondarySamples(for service: ServiceType, since: Date, until: Date) async -> [UsageHistorySecondarySample]
    func availableServices(since: Date, until: Date) async -> [ServiceType]
}

actor UsageHistoryStore: UsageHistoryStoreProtocol {
    private static let schemaVersion = 2
    private static let dayRetentionDays = 365
    private static let secondarySampleRetentionDays = 120
    private static let secondarySampleBucketSeconds: TimeInterval = 5 * 60

    private let fileURL: URL
    private let fileManager: FileManager
    private let calendar: Calendar
    private let nowProvider: @Sendable () -> Date
    private var state: UsageHistoryStoreFile
    private var hasLoaded = false

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default,
        calendar: Calendar = .current,
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.nowProvider = nowProvider
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        self.state = UsageHistoryStoreFile(
            schemaVersion: Self.schemaVersion,
            dayRecords: [],
            secondarySamples: []
        )
    }

    func record(samples: [UsageData], recordedAt: Date) async {
        await ensureLoaded()

        let dayStart = calendar.startOfDay(for: recordedAt)
        for usage in samples where usage.isAvailable {
            let primaryRatio = Self.clampRatio(usage.fiveHourUsage.percentage)
            let secondaryRatio = usage.weeklyUsage.map { Self.clampRatio($0.percentage) }
            let secondaryUsed = usage.weeklyUsage?.used
            let secondaryUnit = usage.weeklyUsage?.unit

            upsertDayRecord(
                service: usage.service,
                dayStart: dayStart,
                primaryRatio: primaryRatio,
                secondaryRatio: secondaryRatio,
                primaryUsed: usage.fiveHourUsage.used,
                secondaryUsed: secondaryUsed,
                primaryUnit: usage.fiveHourUsage.unit,
                secondaryUnit: secondaryUnit,
                recordedAt: recordedAt
            )

            if let weeklyUsage = usage.weeklyUsage,
               let resetTime = weeklyUsage.resetTime {
                upsertSecondarySample(
                    UsageHistorySecondarySample(
                        service: usage.service,
                        sampledAt: Self.truncateToBucket(
                            recordedAt,
                            bucketSeconds: Self.secondarySampleBucketSeconds
                        ),
                        ratio: Self.clampRatio(weeklyUsage.percentage),
                        resetAt: Self.truncateToMinute(resetTime)
                    )
                )
            }
        }

        prune(retainedRelativeTo: recordedAt)
        sortState()
        saveToDisk()
    }

    func dayRecords(for service: ServiceType, since: Date, until: Date) async -> [UsageHistoryDayRecord] {
        await ensureLoaded()
        return state.dayRecords
            .filter { record in
                record.service == service &&
                record.dayStart >= since &&
                record.dayStart <= until
            }
            .sorted { $0.dayStart < $1.dayStart }
    }

    func secondarySamples(
        for service: ServiceType,
        since: Date,
        until: Date
    ) async -> [UsageHistorySecondarySample] {
        await ensureLoaded()
        return state.secondarySamples
            .filter { sample in
                sample.service == service &&
                sample.sampledAt >= since &&
                sample.sampledAt <= until
            }
            .sorted { $0.sampledAt < $1.sampledAt }
    }

    func availableServices(since: Date, until: Date) async -> [ServiceType] {
        await ensureLoaded()

        var serviceSet = Set<ServiceType>()

        for record in state.dayRecords where record.dayStart >= since && record.dayStart <= until {
            serviceSet.insert(record.service)
        }

        for sample in state.secondarySamples where sample.sampledAt >= since && sample.sampledAt <= until {
            serviceSet.insert(sample.service)
        }

        return serviceSet.sorted {
            Self.serviceOrderIndex(for: $0) < Self.serviceOrderIndex(for: $1)
        }
    }

    // MARK: - Day Records

    private func upsertDayRecord(
        service: ServiceType,
        dayStart: Date,
        primaryRatio: Double,
        secondaryRatio: Double?,
        primaryUsed: Double,
        secondaryUsed: Double?,
        primaryUnit: UsageUnit,
        secondaryUnit: UsageUnit?,
        recordedAt: Date
    ) {
        if let index = state.dayRecords.firstIndex(where: {
            $0.service == service && $0.dayStart == dayStart
        }) {
            var record = state.dayRecords[index]
            let previousCount = record.sampleCount
            let nextCount = previousCount + 1

            record.primaryPeakRatio = max(record.primaryPeakRatio, primaryRatio)
            record.primaryAverageRatio = (
                (record.primaryAverageRatio * Double(previousCount)) + primaryRatio
            ) / Double(nextCount)
            let existingPrimaryAverageUsed = record.primaryAverageUsed ?? 0
            record.primaryAverageUsed = (
                (existingPrimaryAverageUsed * Double(previousCount)) + primaryUsed
            ) / Double(nextCount)
            record.primaryPeakUsed = max(record.primaryPeakUsed ?? 0, primaryUsed)
            record.primaryUnitRawValue = primaryUnit.rawValue

            if let secondaryRatio {
                let previousSecondaryAverage = record.secondaryAverageRatio ?? 0
                let nextSecondaryAverage = (
                    (previousSecondaryAverage * Double(previousCount)) + secondaryRatio
                ) / Double(nextCount)
                record.secondaryAverageRatio = nextSecondaryAverage
                record.secondaryPeakRatio = max(record.secondaryPeakRatio ?? 0, secondaryRatio)

                if let secondaryUsed {
                    let existingSecondaryAverageUsed = record.secondaryAverageUsed ?? 0
                    let nextSecondaryAverageUsed = (
                        (existingSecondaryAverageUsed * Double(previousCount)) + secondaryUsed
                    ) / Double(nextCount)
                    record.secondaryAverageUsed = nextSecondaryAverageUsed
                    record.secondaryPeakUsed = max(record.secondaryPeakUsed ?? 0, secondaryUsed)
                }

                if let secondaryUnit {
                    record.secondaryUnitRawValue = secondaryUnit.rawValue
                }
            }

            record.sampleCount = nextCount
            record.lastSampleAt = recordedAt
            state.dayRecords[index] = record
            return
        }

        state.dayRecords.append(
            UsageHistoryDayRecord(
                service: service,
                dayStart: dayStart,
                primaryPeakRatio: primaryRatio,
                primaryAverageRatio: primaryRatio,
                secondaryPeakRatio: secondaryRatio,
                secondaryAverageRatio: secondaryRatio,
                sampleCount: 1,
                lastSampleAt: recordedAt,
                primaryPeakUsed: primaryUsed,
                primaryAverageUsed: primaryUsed,
                primaryUnitRawValue: primaryUnit.rawValue,
                secondaryPeakUsed: secondaryUsed,
                secondaryAverageUsed: secondaryUsed,
                secondaryUnitRawValue: secondaryUnit?.rawValue
            )
        )
    }

    // MARK: - Secondary Samples

    private func upsertSecondarySample(_ sample: UsageHistorySecondarySample) {
        if let index = state.secondarySamples.firstIndex(where: {
            $0.service == sample.service &&
            $0.sampledAt == sample.sampledAt &&
            $0.resetAt == sample.resetAt
        }) {
            let existing = state.secondarySamples[index]
            if sample.ratio > existing.ratio {
                state.secondarySamples[index] = sample
            }
            return
        }

        state.secondarySamples.append(sample)
    }

    // MARK: - Persistence

    private func ensureLoaded() async {
        guard !hasLoaded else { return }
        loadFromDisk()
        hasLoaded = true
    }

    private func loadFromDisk() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            if let decoded = try? JSONDecoder().decode(UsageHistoryStoreFile.self, from: data) {
                state = decoded
                prune(retainedRelativeTo: nowProvider())
                sortState()
                return
            }

            if let legacy = try? JSONDecoder().decode(UsageHistoryStoreFileLegacyV1.self, from: data) {
                state = UsageHistoryStoreFile(
                    schemaVersion: Self.schemaVersion,
                    dayRecords: legacy.records,
                    secondarySamples: []
                )
                prune(retainedRelativeTo: nowProvider())
                sortState()
                saveToDisk()
                return
            }

            backupCorruptStoreFile()
            state = UsageHistoryStoreFile(
                schemaVersion: Self.schemaVersion,
                dayRecords: [],
                secondarySamples: []
            )
            saveToDisk()
        } catch {
            backupCorruptStoreFile()
            state = UsageHistoryStoreFile(
                schemaVersion: Self.schemaVersion,
                dayRecords: [],
                secondarySamples: []
            )
            saveToDisk()
        }
    }

    private func saveToDisk() {
        let directory = fileURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var writableState = state
        writableState.schemaVersion = Self.schemaVersion

        guard let data = try? JSONEncoder().encode(writableState) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func backupCorruptStoreFile() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        let timestamp = Int(nowProvider().timeIntervalSince1970)
        let backupURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("usage-history.corrupt-\(timestamp).json")
        try? fileManager.moveItem(at: fileURL, to: backupURL)
    }

    // MARK: - Retention

    private func prune(retainedRelativeTo now: Date) {
        let dayCutoff = calendar.date(
            byAdding: .day,
            value: -(Self.dayRetentionDays - 1),
            to: calendar.startOfDay(for: now)
        ) ?? calendar.startOfDay(for: now)

        let secondaryCutoff = calendar.date(
            byAdding: .day,
            value: -(Self.secondarySampleRetentionDays - 1),
            to: now
        ) ?? now

        state.dayRecords.removeAll { $0.dayStart < dayCutoff }
        state.secondarySamples.removeAll { $0.sampledAt < secondaryCutoff }
    }

    // MARK: - Helpers

    private func sortState() {
        state.dayRecords.sort {
            if $0.service != $1.service {
                return Self.serviceOrderIndex(for: $0.service) < Self.serviceOrderIndex(for: $1.service)
            }
            return $0.dayStart < $1.dayStart
        }

        state.secondarySamples.sort {
            if $0.service != $1.service {
                return Self.serviceOrderIndex(for: $0.service) < Self.serviceOrderIndex(for: $1.service)
            }
            if $0.resetAt != $1.resetAt {
                return $0.resetAt < $1.resetAt
            }
            return $0.sampledAt < $1.sampledAt
        }
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)

        return baseDirectory
            .appendingPathComponent("AgentBar", isDirectory: true)
            .appendingPathComponent("usage-history.json")
    }

    private static func clampRatio(_ ratio: Double) -> Double {
        min(max(ratio, 0), 1)
    }

    private static func truncateToMinute(_ date: Date) -> Date {
        let seconds = floor(date.timeIntervalSince1970 / 60) * 60
        return Date(timeIntervalSince1970: seconds)
    }

    private static func truncateToBucket(_ date: Date, bucketSeconds: TimeInterval) -> Date {
        let seconds = floor(date.timeIntervalSince1970 / bucketSeconds) * bucketSeconds
        return Date(timeIntervalSince1970: seconds)
    }

    private static func serviceOrderIndex(for service: ServiceType) -> Int {
        let order: [ServiceType] = [.claude, .codex, .gemini, .copilot, .cursor, .opencode, .zai]
        return order.firstIndex(of: service) ?? Int.max
    }
}
