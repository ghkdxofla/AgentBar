import Foundation

protocol AgentAlertEventDetectorProtocol: Sendable {
    var serviceType: ServiceType { get }
    func detectEvents(since: Date, includeBoundary: Bool) async -> [AgentAlertEvent]
}

extension AgentAlertEventDetectorProtocol {
    func detectEvents(since: Date) async -> [AgentAlertEvent] {
        await detectEvents(since: since, includeBoundary: false)
    }
}
