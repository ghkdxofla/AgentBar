import Foundation
import Combine
import os.log

private enum CursorSchema {
    static let legacyVersion = 1
    static let currentVersion = 2
}

@MainActor
final class AgentNotifyMonitor {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.agentbar.app",
        category: "AgentNotifyMonitor"
    )
    private let detectors: [any AgentNotifyEventDetectorProtocol]
    private let notificationService: any AgentNotifyNotificationServiceProtocol
    private let defaults: UserDefaults
    private let cooldown: TimeInterval

    private let socketListener: NotifySocketListener
    private var timerCancellable: AnyCancellable?
    private var settingsCancellable: AnyCancellable?
    private var lastNotificationByKey: [String: Date] = [:]
    private var isProcessing = false

    private static let fallbackPollingInterval: TimeInterval = 10

    init(
        detectors: [any AgentNotifyEventDetectorProtocol]? = nil,
        notificationService: any AgentNotifyNotificationServiceProtocol = AgentNotifyNotificationService(),
        defaults: UserDefaults = .standard,
        cooldown: TimeInterval = 90,
        socketListener: NotifySocketListener? = nil
    ) {
        self.detectors = detectors ?? [CodexNotifyEventDetector(), ClaudeHookNotifyEventDetector()]
        self.notificationService = notificationService
        self.defaults = defaults
        self.cooldown = cooldown
        self.socketListener = socketListener ?? NotifySocketListener()
    }

    func start() {
        ensureInitialWatermarks()
        observeSettingsChangesIfNeeded()

        if isNotificationsEnabled {
            logger.info("Starting notify monitor.")
            Task { await notificationService.requestAuthorizationIfNeeded() }
            startSocketListener()
            restartFallbackTimer()
            Task { await processTick() }
        } else {
            logger.info("Notify monitor remains idle because notifications are disabled.")
        }
    }

    func stop() {
        logger.info("Stopping notify monitor.")
        socketListener.stop()
        timerCancellable?.cancel()
        timerCancellable = nil
        settingsCancellable?.cancel()
        settingsCancellable = nil
    }

    var isSocketListening: Bool {
        socketListener.isListening
    }

    private var isNotificationsEnabled: Bool {
        defaults.bool(forKey: "notificationsEnabled", defaultValue: false)
    }

    private func restartFallbackTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil

        guard !detectors.isEmpty else { return }

        timerCancellable = Timer.publish(every: Self.fallbackPollingInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.processTick() }
            }
    }

    private func startSocketListener() {
        socketListener.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                await self?.receive(event: event)
            }
        }
        socketListener.start()
    }

    func receive(event: AgentNotifyEvent) async {
        guard isNotificationsEnabled else {
            logger.debug("Dropped socket event: notifications disabled.")
            return
        }
        guard isEventEnabled(event.type) else {
            logger.debug("Dropped socket event: disabled type \(event.type.rawValue, privacy: .public).")
            return
        }

        let detectorKey = detectorSettingsKey(for: event.service)
        if let key = detectorKey {
            guard defaults.bool(forKey: key, defaultValue: true) else {
                logger.debug("Dropped socket event: source disabled key=\(key, privacy: .public).")
                return
            }
        }

        guard shouldNotify(event) else {
            logger.debug("Suppressed by cooldown: \(event.dedupeKey, privacy: .public).")
            return
        }

        await notificationService.post(event: event)
        logger.debug(
            "Posted socket event service=\(event.service.rawValue, privacy: .public) type=\(event.type.rawValue, privacy: .public)."
        )
        lastNotificationByKey[event.dedupeKey] = Date()
    }

    private func detectorSettingsKey(for service: ServiceType) -> String? {
        switch service {
        case .claude:
            return "notificationClaudeHookEventsEnabled"
        case .codex:
            return "notificationCodexEventsEnabled"
        case .opencode:
            return "notificationOpencodeHookEventsEnabled"
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
            .publisher(for: .notificationsSettingsChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.isNotificationsEnabled {
                    if !self.socketListener.isListening {
                        self.startSocketListener()
                    }
                    self.restartFallbackTimer()
                    Task { await self.notificationService.requestAuthorizationIfNeeded() }
                    Task { await self.processTick() }
                    self.logger.info("Notifications enabled via settings.")
                } else {
                    self.socketListener.stop()
                    self.timerCancellable?.cancel()
                    self.timerCancellable = nil
                    self.logger.info("Notifications disabled via settings.")
                }
            }
    }

    func processTick() async {
        guard isNotificationsEnabled else {
            logger.debug("Skipped polling tick: notifications disabled.")
            return
        }
        guard !isProcessing else {
            logger.debug("Skipped polling tick: previous tick still running.")
            return
        }

        isProcessing = true
        defer { isProcessing = false }
        ensureInitialWatermarks()

        for detector in detectors {
            guard isDetectorEnabled(detector) else {
                logger.debug(
                    "Skipped detector \(detector.serviceType.rawValue, privacy: .public): source disabled."
                )
                continue
            }

            let serviceType = detector.serviceType
            let watermark = watermarkCursor(for: serviceType)
            let includeBoundary = hasStoredWatermarkEventIDs(for: serviceType)
            let events = await Task.detached(priority: .utility) {
                await detector.detectEvents(since: watermark.date, includeBoundary: includeBoundary)
            }.value

            guard !events.isEmpty else { continue }
            logger.debug(
                "Detector \(serviceType.rawValue, privacy: .public) produced \(events.count, privacy: .public) events."
            )
            let unseenEvents = events.filter { !isAlreadyProcessed($0, at: watermark) }

            if !unseenEvents.isEmpty {
                for event in unseenEvents {
                    guard isEventEnabled(event.type) else {
                        logger.debug(
                            "Dropped polled event: type disabled \(event.type.rawValue, privacy: .public)."
                        )
                        continue
                    }
                    guard shouldNotify(event) else {
                        logger.debug("Suppressed by cooldown: \(event.dedupeKey, privacy: .public).")
                        continue
                    }

                    await notificationService.post(event: event)
                    logger.debug(
                        "Posted polled event service=\(event.service.rawValue, privacy: .public) type=\(event.type.rawValue, privacy: .public)."
                    )
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

    private func shouldNotify(_ event: AgentNotifyEvent) -> Bool {
        if let previous = lastNotificationByKey[event.dedupeKey],
           Date().timeIntervalSince(previous) < cooldown {
            return false
        }
        return true
    }

    private func isEventEnabled(_ type: AgentNotifyEventType) -> Bool {
        defaults.bool(forKey: type.settingsKey, defaultValue: true)
    }

    private func isDetectorEnabled(_ detector: any AgentNotifyEventDetectorProtocol) -> Bool {
        guard let key = detector.settingsEnabledKey else { return true }
        return defaults.bool(forKey: key, defaultValue: true)
    }

    private func watermarkKey(for service: ServiceType) -> String {
        let normalized = service.rawValue
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        return "notificationLastSeen_\(normalized)"
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

    private func isAlreadyProcessed(_ event: AgentNotifyEvent, at watermark: WatermarkCursor) -> Bool {
        guard areSameTimestamp(event.timestamp, watermark.date) else { return false }

        if watermark.eventIDsAtTimestamp.contains(event.cursorID) {
            return true
        }

        if watermark.schemaVersion < CursorSchema.currentVersion {
            return watermark.eventIDsAtTimestamp.contains(event.legacyCursorID)
        }

        return false
    }

    private func updatedWatermarkCursor(from current: WatermarkCursor, with events: [AgentNotifyEvent]) -> WatermarkCursor {
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
