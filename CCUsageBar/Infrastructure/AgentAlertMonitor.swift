import Foundation
import Combine

@MainActor
final class AgentAlertMonitor {
    private let detectors: [any AgentAlertEventDetectorProtocol]
    private let notificationService: AgentAlertNotificationService
    private let defaults: UserDefaults
    private let cooldown: TimeInterval

    private var timerCancellable: AnyCancellable?
    private var settingsCancellable: AnyCancellable?
    private var lastNotificationByKey: [String: Date] = [:]
    private var isProcessing = false

    init(
        detectors: [any AgentAlertEventDetectorProtocol]? = nil,
        notificationService: AgentAlertNotificationService = AgentAlertNotificationService(),
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
            if defaults.object(forKey: key) == nil {
                defaults.set(now, forKey: key)
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

    private func processTick() async {
        guard isAlertsEnabled else { return }
        guard !isProcessing else { return }

        isProcessing = true
        defer { isProcessing = false }

        for detector in detectors {
            let key = watermarkKey(for: detector.serviceType)
            let lastSeen = Date(timeIntervalSince1970: defaults.double(forKey: key))
            let events = await detector.detectEvents(since: lastSeen)

            guard !events.isEmpty else { continue }

            var maxTimestamp = lastSeen
            for event in events {
                if event.timestamp > maxTimestamp {
                    maxTimestamp = event.timestamp
                }

                guard isEventEnabled(event.type) else { continue }
                guard shouldNotify(event) else { continue }

                await notificationService.post(event: event)
                lastNotificationByKey[event.dedupeKey] = Date()
            }

            defaults.set(maxTimestamp.timeIntervalSince1970, forKey: key)
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
}

private extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        guard object(forKey: key) != nil else { return defaultValue }
        return bool(forKey: key)
    }
}

