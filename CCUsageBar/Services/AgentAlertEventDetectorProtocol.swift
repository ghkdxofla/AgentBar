import Foundation

protocol AgentAlertEventDetectorProtocol: Sendable {
    var serviceType: ServiceType { get }
    var settingsEnabledKey: String? { get }
    func detectEvents(since: Date, includeBoundary: Bool) async -> [AgentAlertEvent]
}

extension AgentAlertEventDetectorProtocol {
    var settingsEnabledKey: String? {
        nil
    }

    func detectEvents(since: Date) async -> [AgentAlertEvent] {
        await detectEvents(since: since, includeBoundary: false)
    }
}
