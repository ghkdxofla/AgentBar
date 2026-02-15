import Foundation
import Combine

@MainActor
final class AgentAlertMonitor {
    private let detectors: [any AgentAlertEventDetectorProtocol]
    private let notificationService: any AgentAlertNotificationServiceProtocol
    private let defaults: UserDefaults
    private let cooldown: TimeInterval

    private var timerCancellable: AnyCancellable?
    private var settingsCancellable: AnyCancellable?
    private var lastNotificationByKey: [String: Date] = [:]
    private var isProcessing = false

    init(
        detectors: [any AgentAlertEventDetectorProtocol]? = nil,
        notificationService: any AgentAlertNotificationServiceProtocol = AgentAlertNotificationService(),
        defaults: UserDefaults = .standard,
        cooldown: TimeInterval = 90
    ) {
        self.detectors = detectors ?? [CodexAlertEventDetector()]
        self.notificationService = notificationService
        self.defaults = defaults
        self.cooldown = cooldown
    }

    func start() {
        ensureInitialWatermarks()
        observeSettingsChangesIfNeeded()
        restartPollingTimer()

        if isAlertsEnabled {
            Task { await notificationService.requestAuthorizationIfNeeded() }
            Task { await processTick() }
        }
    }

    func stop() {
        timerCancellable?.cancel()
        timerCancellable = nil
        settingsCancellable?.cancel()
        settingsCancellable = nil
    }

    private var isAlertsEnabled: Bool {
        defaults.bool(forKey: "alertsEnabled", defaultValue: false)
    }

    private var pollingInterval: TimeInterval {
        let stored = defaults.double(forKey: "alertPollingSeconds")
        return stored > 0 ? stored : 5
    }

    private func ensureInitialWatermarks() {
        let now = Date().timeIntervalSince1970
        for detector in detectors {
            let key = watermarkKey(for: detector.serviceType)
            let eventIDsKey = watermarkEventIDsKey(for: detector.serviceType)

            if defaults.object(forKey: key) == nil {
                // New installs start with both timestamp and boundary IDs initialized.
                defaults.set(now, forKey: key)
                defaults.set([String](), forKey: eventIDsKey)
            }
        }
    }

    private func observeSettingsChangesIfNeeded() {
        guard settingsCancellable == nil else { return }

        settingsCancellable = NotificationCenter.default
            .publisher(for: .alertsSettingsChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.restartPollingTimer()
                if self.isAlertsEnabled {
                    Task { await self.notificationService.requestAuthorizationIfNeeded() }
                    Task { await self.processTick() }
                }
            }
    }

    private func restartPollingTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil

        timerCancellable = Timer.publish(every: pollingInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.processTick() }
            }
    }

    func processTick() async {
        guard isAlertsEnabled else { return }
        guard !isProcessing else { return }

        isProcessing = true
        defer { isProcessing = false }
        ensureInitialWatermarks()

        for detector in detectors {
            let serviceType = detector.serviceType
            let watermark = watermarkCursor(for: serviceType)
            // Legacy installs may have a timestamp but no ID set; stay boundary-exclusive until the cursor advances.
            let includeBoundary = hasStoredWatermarkEventIDs(for: serviceType)
            let events = await Task.detached(priority: .utility) {
                await detector.detectEvents(since: watermark.date, includeBoundary: includeBoundary)
            }.value

            guard !events.isEmpty else { continue }
            let unseenEvents = events.filter { !isAlreadyProcessed($0, at: watermark) }
            guard !unseenEvents.isEmpty else { continue }

            for event in unseenEvents {
                guard isEventEnabled(event.type) else { continue }
                guard shouldNotify(event) else { continue }

                await notificationService.post(event: event)
                lastNotificationByKey[event.dedupeKey] = Date()
            }

            let updatedWatermark = updatedWatermarkCursor(from: watermark, with: unseenEvents)
            if includeBoundary || !areSameTimestamp(updatedWatermark.date, watermark.date) {
                saveWatermarkCursor(updatedWatermark, for: serviceType)
            }
        }
    }

    private func shouldNotify(_ event: AgentAlertEvent) -> Bool {
        if let previous = lastNotificationByKey[event.dedupeKey],
           Date().timeIntervalSince(previous) < cooldown {
            return false
        }
        return true
    }

    private func isEventEnabled(_ type: AgentAlertEventType) -> Bool {
        defaults.bool(forKey: type.settingsKey, defaultValue: true)
    }

    private func watermarkKey(for service: ServiceType) -> String {
        let normalized = service.rawValue
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        return "alertLastSeen_\(normalized)"
    }

    private func watermarkEventIDsKey(for service: ServiceType) -> String {
        "\(watermarkKey(for: service))_eventIDs"
    }

    private func watermarkCursor(for service: ServiceType) -> WatermarkCursor {
        let timestampKey = watermarkKey(for: service)
        let timestamp = defaults.double(forKey: timestampKey)
        let eventIDs = Set(defaults.stringArray(forKey: watermarkEventIDsKey(for: service)) ?? [])
        return WatermarkCursor(timestamp: timestamp, eventIDsAtTimestamp: eventIDs)
    }

    private func hasStoredWatermarkEventIDs(for service: ServiceType) -> Bool {
        defaults.object(forKey: watermarkEventIDsKey(for: service)) != nil
    }

    private func saveWatermarkCursor(_ cursor: WatermarkCursor, for service: ServiceType) {
        defaults.set(cursor.timestamp, forKey: watermarkKey(for: service))
        defaults.set(Array(cursor.eventIDsAtTimestamp).sorted(), forKey: watermarkEventIDsKey(for: service))
    }

    private func isAlreadyProcessed(_ event: AgentAlertEvent, at watermark: WatermarkCursor) -> Bool {
        guard areSameTimestamp(event.timestamp, watermark.date) else { return false }
        return watermark.eventIDsAtTimestamp.contains(event.cursorID)
    }

    private func updatedWatermarkCursor(from current: WatermarkCursor, with events: [AgentAlertEvent]) -> WatermarkCursor {
        guard let maxTimestamp = events.map(\.timestamp).max() else { return current }

        if areSameTimestamp(maxTimestamp, current.date) {
            var merged = current.eventIDsAtTimestamp
            for event in events where areSameTimestamp(event.timestamp, maxTimestamp) {
                merged.insert(event.cursorID)
            }
            return WatermarkCursor(timestamp: current.timestamp, eventIDsAtTimestamp: merged)
        }

        let idsAtMaxTimestamp = Set(
            events
                .filter { areSameTimestamp($0.timestamp, maxTimestamp) }
                .map(\.cursorID)
        )
        return WatermarkCursor(
            timestamp: maxTimestamp.timeIntervalSince1970,
            eventIDsAtTimestamp: idsAtMaxTimestamp
        )
    }

    private func areSameTimestamp(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince1970 - rhs.timeIntervalSince1970) < 0.000_001
    }
}

private struct WatermarkCursor: Sendable {
    let timestamp: TimeInterval
    let eventIDsAtTimestamp: Set<String>

    var date: Date {
        Date(timeIntervalSince1970: timestamp)
    }
}

private extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        guard object(forKey: key) != nil else { return defaultValue }
        return bool(forKey: key)
    }
}
