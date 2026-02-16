import Foundation

protocol AgentNotifyEventDetectorProtocol: Sendable {
    var serviceType: ServiceType { get }
    var settingsEnabledKey: String? { get }
    func detectEvents(since: Date, includeBoundary: Bool) async -> [AgentNotifyEvent]
}

extension AgentNotifyEventDetectorProtocol {
    var settingsEnabledKey: String? {
        nil
    }

    func detectEvents(since: Date) async -> [AgentNotifyEvent] {
        await detectEvents(since: since, includeBoundary: false)
    }

    func passesBoundary(_ date: Date, since: Date, includeBoundary: Bool) -> Bool {
        includeBoundary ? date >= since : date > since
    }
}
