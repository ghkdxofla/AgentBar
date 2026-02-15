import Foundation

protocol AgentAlertEventDetectorProtocol: Sendable {
    var serviceType: ServiceType { get }
    func detectEvents(since: Date) async -> [AgentAlertEvent]
}

