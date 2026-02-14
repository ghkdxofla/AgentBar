import Foundation

struct ClaudeMessageRecord: Decodable, Sendable {
    let type: String?
    let timestamp: String?
    let costUSD: Double?
    let usage: ClaudeTokenUsage?
    let model: String?

    // Support sub-agent messages that have nested message.usage
    let message: ClaudeNestedMessage?
}

struct ClaudeNestedMessage: Decodable, Sendable {
    let id: String?
    let usage: ClaudeTokenUsage?
}

struct ClaudeTokenUsage: Decodable, Sendable {
    let input_tokens: Int?
    let output_tokens: Int?
    let cache_read_input_tokens: Int?
    let cache_creation_input_tokens: Int?

    /// Compute API-equivalent cost using model-specific pricing ($/M tokens)
    func cost(pricing: ClaudeModelPricing) -> Double {
        Double(input_tokens ?? 0) * pricing.input / 1_000_000
        + Double(output_tokens ?? 0) * pricing.output / 1_000_000
        + Double(cache_creation_input_tokens ?? 0) * pricing.cacheCreation / 1_000_000
        + Double(cache_read_input_tokens ?? 0) * pricing.cacheRead / 1_000_000
    }
}

struct ClaudeModelPricing: Sendable {
    let input: Double       // $/M tokens
    let output: Double
    let cacheCreation: Double
    let cacheRead: Double

    static func forModel(_ model: String?) -> ClaudeModelPricing {
        guard let model = model?.lowercased() else { return .opus }
        if model.contains("opus")   { return .opus }
        if model.contains("sonnet") { return .sonnet }
        if model.contains("haiku")  { return .haiku }
        return .opus // default to most expensive
    }

    static let opus   = ClaudeModelPricing(input: 15.0, output: 75.0, cacheCreation: 18.75, cacheRead: 1.50)
    static let sonnet = ClaudeModelPricing(input: 3.0,  output: 15.0, cacheCreation: 3.75,  cacheRead: 0.30)
    static let haiku  = ClaudeModelPricing(input: 0.80, output: 4.0,  cacheCreation: 1.00,  cacheRead: 0.08)
}

final class ClaudeUsageProvider: UsageProviderProtocol, @unchecked Sendable {
    let serviceType: ServiceType = .claude

    private let projectsDir: URL
    private let fiveHourBudget: Double
    private let weeklyBudget: Double

    init(
        projectsDir: URL? = nil,
        fiveHourBudget: Double = 103.0,
        weeklyBudget: Double = 1133.0
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.projectsDir = projectsDir ?? home.appendingPathComponent(".claude/projects")
        self.fiveHourBudget = fiveHourBudget
        self.weeklyBudget = weeklyBudget
    }

    func isConfigured() async -> Bool {
        FileManager.default.fileExists(atPath: projectsDir.path)
    }

    func fetchUsage() async throws -> UsageData {
        let now = Date()
        let records = try scanRecentRecords(now: now)

        // Deduplicate by message ID — keep only the last record per ID
        let deduplicated = deduplicateByMessageID(records)

        let fiveHourRecords = deduplicated.filter { rec in
            guard let ts = rec.timestamp, let date = DateUtils.parseISO8601(ts) else { return false }
            return DateUtils.isWithinFiveHourWindow(date, relativeTo: now)
        }

        let weeklyRecords = deduplicated.filter { rec in
            guard let ts = rec.timestamp, let date = DateUtils.parseISO8601(ts) else { return false }
            return DateUtils.isWithinWeeklyWindow(date, relativeTo: now)
        }

        let fiveHourCost = totalCost(from: fiveHourRecords)
        let weeklyCost = totalCost(from: weeklyRecords)

        // Rolling window: earliest record in window + window duration = when usage starts dropping
        let fiveHourReset = earliestTimestamp(from: fiveHourRecords)
            .map { $0.addingTimeInterval(DateUtils.fiveHourInterval) }
        let weeklyReset = earliestTimestamp(from: weeklyRecords)
            .map { $0.addingTimeInterval(DateUtils.weeklyInterval) }

        return UsageData(
            service: .claude,
            fiveHourUsage: UsageMetric(
                used: fiveHourCost,
                total: fiveHourBudget,
                unit: .dollars,
                resetTime: fiveHourReset
            ),
            weeklyUsage: UsageMetric(
                used: weeklyCost,
                total: weeklyBudget,
                unit: .dollars,
                resetTime: weeklyReset
            ),
            lastUpdated: now,
            isAvailable: true
        )
    }

    // MARK: - Private

    private func scanRecentRecords(now: Date) throws -> [ClaudeMessageRecord] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: projectsDir.path) else {
            return []
        }

        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 3600)
        var allRecords: [ClaudeMessageRecord] = []

        let projectDirs = try fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        for dir in projectDirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            let files = try fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            for file in files {
                guard file.pathExtension == "jsonl" else { continue }

                if let attrs = try? fm.attributesOfItem(atPath: file.path),
                   let modDate = attrs[.modificationDate] as? Date,
                   modDate < sevenDaysAgo {
                    continue
                }

                let records = try JSONLParser.parseFile(file, as: ClaudeMessageRecord.self)
                allRecords.append(contentsOf: records)
            }
        }

        return allRecords
    }

    private func deduplicateByMessageID(_ records: [ClaudeMessageRecord]) -> [ClaudeMessageRecord] {
        var lastByID: [String: ClaudeMessageRecord] = [:]
        var noIDRecords: [ClaudeMessageRecord] = []

        for record in records {
            guard record.type == "assistant" else { continue }
            if let msgID = record.message?.id {
                lastByID[msgID] = record
            } else {
                noIDRecords.append(record)
            }
        }

        return Array(lastByID.values) + noIDRecords
    }

    private func earliestTimestamp(from records: [ClaudeMessageRecord]) -> Date? {
        records.compactMap { $0.timestamp }
            .compactMap { DateUtils.parseISO8601($0) }
            .min()
    }

    private func totalCost(from records: [ClaudeMessageRecord]) -> Double {
        records.reduce(0.0) { sum, record in
            guard let usage = record.message?.usage else { return sum }
            let pricing = ClaudeModelPricing.forModel(record.model)
            return sum + usage.cost(pricing: pricing)
        }
    }
}
