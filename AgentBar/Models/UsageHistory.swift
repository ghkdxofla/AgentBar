import Foundation

struct UsageHistoryDayRecord: Codable, Sendable, Equatable {
    let service: ServiceType
    let dayStart: Date
    var primaryPeakRatio: Double
    var primaryAverageRatio: Double
    var secondaryPeakRatio: Double?
    var secondaryAverageRatio: Double?
    var sampleCount: Int
    var lastSampleAt: Date
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
