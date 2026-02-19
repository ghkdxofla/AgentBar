import Foundation

struct UsageHistoryDayRecord: Codable, Sendable, Equatable {
    let service: ServiceType
    let dayStart: Date
    var primaryPeakRatio: Double
    var primaryAverageRatio: Double
    var secondaryPeakRatio: Double?
    var secondaryAverageRatio: Double?
    var sampleCount: Int
    var secondarySampleCount: Int
    var lastSampleAt: Date
    var primaryPeakUsed: Double? = nil
    var primaryAverageUsed: Double? = nil
    var primaryUnitRawValue: String? = nil
    var secondaryPeakUsed: Double? = nil
    var secondaryAverageUsed: Double? = nil
    var secondaryUnitRawValue: String? = nil

    enum CodingKeys: String, CodingKey {
        case service
        case dayStart
        case primaryPeakRatio
        case primaryAverageRatio
        case secondaryPeakRatio
        case secondaryAverageRatio
        case sampleCount
        case secondarySampleCount
        case lastSampleAt
        case primaryPeakUsed
        case primaryAverageUsed
        case primaryUnitRawValue
        case secondaryPeakUsed
        case secondaryAverageUsed
        case secondaryUnitRawValue
    }

    init(
        service: ServiceType,
        dayStart: Date,
        primaryPeakRatio: Double,
        primaryAverageRatio: Double,
        secondaryPeakRatio: Double?,
        secondaryAverageRatio: Double?,
        sampleCount: Int,
        secondarySampleCount: Int = 0,
        lastSampleAt: Date,
        primaryPeakUsed: Double? = nil,
        primaryAverageUsed: Double? = nil,
        primaryUnitRawValue: String? = nil,
        secondaryPeakUsed: Double? = nil,
        secondaryAverageUsed: Double? = nil,
        secondaryUnitRawValue: String? = nil
    ) {
        self.service = service
        self.dayStart = dayStart
        self.primaryPeakRatio = primaryPeakRatio
        self.primaryAverageRatio = primaryAverageRatio
        self.secondaryPeakRatio = secondaryPeakRatio
        self.secondaryAverageRatio = secondaryAverageRatio
        self.sampleCount = sampleCount
        self.secondarySampleCount = secondarySampleCount
        self.lastSampleAt = lastSampleAt
        self.primaryPeakUsed = primaryPeakUsed
        self.primaryAverageUsed = primaryAverageUsed
        self.primaryUnitRawValue = primaryUnitRawValue
        self.secondaryPeakUsed = secondaryPeakUsed
        self.secondaryAverageUsed = secondaryAverageUsed
        self.secondaryUnitRawValue = secondaryUnitRawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedService = try container.decode(ServiceType.self, forKey: .service)
        let decodedDayStart = try container.decode(Date.self, forKey: .dayStart)
        let decodedPrimaryPeakRatio = try container.decode(Double.self, forKey: .primaryPeakRatio)
        let decodedPrimaryAverageRatio = try container.decode(Double.self, forKey: .primaryAverageRatio)
        let decodedSecondaryPeakRatio = try container.decodeIfPresent(Double.self, forKey: .secondaryPeakRatio)
        let decodedSecondaryAverageRatio = try container.decodeIfPresent(Double.self, forKey: .secondaryAverageRatio)
        let decodedSampleCount = try container.decode(Int.self, forKey: .sampleCount)
        let decodedLastSampleAt = try container.decode(Date.self, forKey: .lastSampleAt)

        let hasSecondaryData = decodedSecondaryPeakRatio != nil || decodedSecondaryAverageRatio != nil
        let decodedSecondarySampleCount = try container.decodeIfPresent(Int.self, forKey: .secondarySampleCount)
            ?? (hasSecondaryData ? decodedSampleCount : 0)

        self.init(
            service: decodedService,
            dayStart: decodedDayStart,
            primaryPeakRatio: decodedPrimaryPeakRatio,
            primaryAverageRatio: decodedPrimaryAverageRatio,
            secondaryPeakRatio: decodedSecondaryPeakRatio,
            secondaryAverageRatio: decodedSecondaryAverageRatio,
            sampleCount: decodedSampleCount,
            secondarySampleCount: decodedSecondarySampleCount,
            lastSampleAt: decodedLastSampleAt,
            primaryPeakUsed: try container.decodeIfPresent(Double.self, forKey: .primaryPeakUsed),
            primaryAverageUsed: try container.decodeIfPresent(Double.self, forKey: .primaryAverageUsed),
            primaryUnitRawValue: try container.decodeIfPresent(String.self, forKey: .primaryUnitRawValue),
            secondaryPeakUsed: try container.decodeIfPresent(Double.self, forKey: .secondaryPeakUsed),
            secondaryAverageUsed: try container.decodeIfPresent(Double.self, forKey: .secondaryAverageUsed),
            secondaryUnitRawValue: try container.decodeIfPresent(String.self, forKey: .secondaryUnitRawValue)
        )
    }
}

struct UsageHistorySecondarySample: Codable, Sendable, Equatable {
    let service: ServiceType
    let sampledAt: Date
    let ratio: Double
    let resetAt: Date
}

struct UsageHistoryStoreFile: Codable, Sendable {
    var schemaVersion: Int
    var dayRecords: [UsageHistoryDayRecord]
    var secondarySamples: [UsageHistorySecondarySample]
}

struct UsageHistoryStoreFileLegacyV1: Codable, Sendable {
    var schemaVersion: Int
    var records: [UsageHistoryDayRecord]
}

enum UsageHistoryWindow: String, CaseIterable, Sendable {
    case primary
    case secondary
}
