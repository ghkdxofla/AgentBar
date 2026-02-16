import Foundation
import Combine

private enum CursorSchema {
    static let legacyVersion = 1
    static let currentVersion = 2
}

@MainActor
final class AgentAlertMonitor {
    private let detectors: [any AgentAlertEventDetectorProtocol]
    private let notificationService: any AgentAlertNotificationServiceProtocol
    private let defaults: UserDefaults
    private let cooldown: TimeInterval

    private let socketListener: AlertSocketListener
    private var settingsCancellable: AnyCancellable?
    private var lastNotificationByKey: [String: Date] = [:]
    private var isProcessing = false

    init(
        detectors: [any AgentAlertEventDetectorProtocol]? = nil,
        notificationService: any AgentAlertNotificationServiceProtocol = AgentAlertNotificationService(),
        defaults: UserDefaults = .standard,
        cooldown: TimeInterval = 90,
        socketListener: AlertSocketListener? = nil
    ) {
        self.detectors = detectors ?? [CodexAlertEventDetector()]
        self.notificationService = notificationService
        self.defaults = defaults
        self.cooldown = cooldown
        self.socketListener = socketListener ?? AlertSocketListener()
    }

    func start() {
        ensureInitialWatermarks()
        observeSettingsChangesIfNeeded()

        if isAlertsEnabled {
            Task { await notificationService.requestAuthorizationIfNeeded() }
            startSocketListener()
            Task { await processTick() }
        }
    }

    func stop() {
        socketListener.stop()
        settingsCancellable?.cancel()
        settingsCancellable = nil
    }

    var isSocketListening: Bool {
        socketListener.isListening
    }

    private var isAlertsEnabled: Bool {
        defaults.bool(forKey: "alertsEnabled", defaultValue: false)
    }

    private func startSocketListener() {
        socketListener.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                await self?.receive(event: event)
            }
        }
        socketListener.start()
    }

    func receive(event: AgentAlertEvent) async {
        guard isAlertsEnabled else { return }
        guard isEventEnabled(event.type) else { return }

        let detectorKey = detectorSettingsKey(for: event.service)
        if let key = detectorKey {
            guard defaults.bool(forKey: key, defaultValue: true) else { return }
        }

        guard shouldNotify(event) else { return }

        await notificationService.post(event: event)
        lastNotificationByKey[event.dedupeKey] = Date()
    }

    private func detectorSettingsKey(for service: ServiceType) -> String? {
        switch service {
        case .claude:
            return "alertClaudeHookEventsEnabled"
        case .codex:
            return "alertCodexEventsEnabled"
        default:
            return nil
        }
    }

    private func ensureInitialWatermarks() {
        let now = Date().timeIntervalSince1970
        for detector in detectors {
            let key = watermarkKey(for: detector.serviceType)
            let eventIDsKey = watermarkEventIDsKey(for: detector.serviceType)
            let schemaVersionKey = watermarkSchemaVersionKey(for: detector.serviceType)

            if defaults.object(forKey: key) == nil {
                defaults.set(now, forKey: key)
                defaults.set([String](), forKey: eventIDsKey)
                defaults.set(CursorSchema.currentVersion, forKey: schemaVersionKey)
                continue
            }

            if defaults.object(forKey: schemaVersionKey) == nil {
                defaults.set(CursorSchema.legacyVersion, forKey: schemaVersionKey)
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
                if self.isAlertsEnabled {
                    if !self.socketListener.isListening {
                        self.startSocketListener()
                    }
                    Task { await self.notificationService.requestAuthorizationIfNeeded() }
                    Task { await self.processTick() }
                } else {
                    self.socketListener.stop()
                }
            }
    }

    func processTick() async {
        guard isAlertsEnabled else { return }
        guard !isProcessing else { return }

        isProcessing = true
        defer { isProcessing = false }
        ensureInitialWatermarks()

        for detector in detectors {
            guard isDetectorEnabled(detector) else { continue }

            let serviceType = detector.serviceType
            let watermark = watermarkCursor(for: serviceType)
            let includeBoundary = hasStoredWatermarkEventIDs(for: serviceType)
            let events = await Task.detached(priority: .utility) {
                await detector.detectEvents(since: watermark.date, includeBoundary: includeBoundary)
            }.value

            guard !events.isEmpty else { continue }
            let unseenEvents = events.filter { !isAlreadyProcessed($0, at: watermark) }

            if !unseenEvents.isEmpty {
                for event in unseenEvents {
                    guard isEventEnabled(event.type) else { continue }
                    guard shouldNotify(event) else { continue }

                    await notificationService.post(event: event)
                    lastNotificationByKey[event.dedupeKey] = Date()
                }
            }

            let eventsForCursorUpdate = watermark.schemaVersion < CursorSchema.currentVersion ? events : unseenEvents
            guard !eventsForCursorUpdate.isEmpty else { continue }

            let updatedWatermark = updatedWatermarkCursor(from: watermark, with: eventsForCursorUpdate)
            if includeBoundary ||
                !areSameTimestamp(updatedWatermark.date, watermark.date) ||
                watermark.schemaVersion < CursorSchema.currentVersion {
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

    private func isDetectorEnabled(_ detector: any AgentAlertEventDetectorProtocol) -> Bool {
        guard let key = detector.settingsEnabledKey else { return true }
        return defaults.bool(forKey: key, defaultValue: true)
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

    private func watermarkSchemaVersionKey(for service: ServiceType) -> String {
        "\(watermarkKey(for: service))_cursorSchemaVersion"
    }

    private func watermarkCursor(for service: ServiceType) -> WatermarkCursor {
        let timestampKey = watermarkKey(for: service)
        let timestamp = defaults.double(forKey: timestampKey)
        let eventIDs = Set(defaults.stringArray(forKey: watermarkEventIDsKey(for: service)) ?? [])
        let schemaVersion = defaults.object(forKey: watermarkSchemaVersionKey(for: service)) != nil
            ? defaults.integer(forKey: watermarkSchemaVersionKey(for: service))
            : CursorSchema.legacyVersion
        return WatermarkCursor(
            timestamp: timestamp,
            eventIDsAtTimestamp: eventIDs,
            schemaVersion: schemaVersion
        )
    }

    private func hasStoredWatermarkEventIDs(for service: ServiceType) -> Bool {
        defaults.object(forKey: watermarkEventIDsKey(for: service)) != nil
    }

    private func saveWatermarkCursor(_ cursor: WatermarkCursor, for service: ServiceType) {
        defaults.set(cursor.timestamp, forKey: watermarkKey(for: service))
        defaults.set(Array(cursor.eventIDsAtTimestamp).sorted(), forKey: watermarkEventIDsKey(for: service))
        defaults.set(cursor.schemaVersion, forKey: watermarkSchemaVersionKey(for: service))
    }

    private func isAlreadyProcessed(_ event: AgentAlertEvent, at watermark: WatermarkCursor) -> Bool {
        guard areSameTimestamp(event.timestamp, watermark.date) else { return false }

        if watermark.eventIDsAtTimestamp.contains(event.cursorID) {
            return true
        }

        if watermark.schemaVersion < CursorSchema.currentVersion {
            return watermark.eventIDsAtTimestamp.contains(event.legacyCursorID)
        }

        return false
    }

    private func updatedWatermarkCursor(from current: WatermarkCursor, with events: [AgentAlertEvent]) -> WatermarkCursor {
        guard let maxTimestamp = events.map(\.timestamp).max() else { return current }

        if areSameTimestamp(maxTimestamp, current.date) {
            var merged = current.eventIDsAtTimestamp
            for event in events where areSameTimestamp(event.timestamp, maxTimestamp) {
                merged.insert(event.cursorID)
            }
            return WatermarkCursor(
                timestamp: current.timestamp,
                eventIDsAtTimestamp: merged,
                schemaVersion: CursorSchema.currentVersion
            )
        }

        let idsAtMaxTimestamp = Set(
            events
                .filter { areSameTimestamp($0.timestamp, maxTimestamp) }
                .map(\.cursorID)
        )
        return WatermarkCursor(
            timestamp: maxTimestamp.timeIntervalSince1970,
            eventIDsAtTimestamp: idsAtMaxTimestamp,
            schemaVersion: CursorSchema.currentVersion
        )
    }

    private func areSameTimestamp(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince1970 - rhs.timeIntervalSince1970) < 0.000_001
    }
}

private struct WatermarkCursor: Sendable {
    let timestamp: TimeInterval
    let eventIDsAtTimestamp: Set<String>
    let schemaVersion: Int

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
