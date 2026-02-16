import Foundation
import UserNotifications

protocol AgentAlertNotificationServiceProtocol: Sendable {
    func requestAuthorizationIfNeeded() async
    func post(event: AgentAlertEvent) async
}

actor AgentAlertNotificationService: AgentAlertNotificationServiceProtocol {
    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private let postBodyOverride: (@Sendable (String) async throws -> Void)?
    private var didCheckAuthorization = false

    init(
        center: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard,
        postBodyOverride: (@Sendable (String) async throws -> Void)? = nil
    ) {
        self.center = center
        self.defaults = defaults
        self.postBodyOverride = postBodyOverride
    }

    nonisolated static func requestAuthorizationPrompt() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func requestAuthorizationIfNeeded() async {
        guard !didCheckAuthorization else { return }
        didCheckAuthorization = true

        let statusRawValue = await authorizationStatusRawValue()
        guard statusRawValue == UNAuthorizationStatus.notDetermined.rawValue else { return }
        _ = await requestAuthorization()
    }

    func post(event: AgentAlertEvent) async {
        let content = UNMutableNotificationContent()
        content.title = event.type.notificationTitle
        let showMessagePreview = bool(forKey: "alertShowMessagePreview", defaultValue: false)
        let body = showMessagePreview ? event.notificationBody : event.redactedNotificationBody
        content.body = "[\(event.service.rawValue)] \(body)"

        let didPlayCustomSound = AlertSoundManager.shared.play(for: event.type)
        content.sound = didPlayCustomSound ? nil : .default

        let request = UNNotificationRequest(
            identifier: "agentbar-agent-alert-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            if let postBodyOverride {
                try await postBodyOverride(content.body)
            } else {
                try await add(request)
            }
        } catch {
            // Ignore posting failures so monitoring loop can continue.
        }
    }

    private func authorizationStatusRawValue() async -> Int {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus.rawValue)
            }
        }
    }

    private func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    private func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func bool(forKey key: String, defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }
}
