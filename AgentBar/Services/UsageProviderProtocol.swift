import Foundation

protocol UsageProviderProtocol: Sendable {
    var serviceType: ServiceType { get }
    func isConfigured() async -> Bool
    func fetchUsage() async throws -> UsageData
}
