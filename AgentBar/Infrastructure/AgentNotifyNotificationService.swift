import Foundation
import UserNotifications
import os.log

protocol AgentNotifyNotificationServiceProtocol: Sendable {
    func requestAuthorizationIfNeeded() async
    func post(event: AgentNotifyEvent) async
}

actor AgentNotifyNotificationService: AgentNotifyNotificationServiceProtocol {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.agentbar.app",
        category: "AgentNotifyNotificationService"
    )
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
        guard !didCheckAuthorization else {
            logger.debug("Skipping authorization check: already performed.")
            return
        }
        didCheckAuthorization = true

        let statusRawValue = await authorizationStatusRawValue()
        guard statusRawValue == UNAuthorizationStatus.notDetermined.rawValue else {
            logger.debug("Authorization status already determined: \(statusRawValue, privacy: .public).")
            return
        }
        let granted = await requestAuthorization()
        logger.info("Notification permission prompt completed. granted=\(granted, privacy: .public).")
    }

    func post(event: AgentNotifyEvent) async {
        let content = UNMutableNotificationContent()
        content.title = event.type.notificationTitle
        let showMessagePreview = defaults.bool(forKey: "notificationShowMessagePreview", defaultValue: false)
        let body = showMessagePreview ? event.notificationBody : event.redactedNotificationBody
        content.body = "\(event.notificationSourceTag) \(body)"

        let didPlayCustomSound = NotifySoundManager.shared.play(for: event.type)
        content.sound = didPlayCustomSound ? nil : .default

        let request = UNNotificationRequest(
            identifier: "agentbar-agent-notify-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            if let postBodyOverride {
                try await postBodyOverride(content.body)
            } else {
                try await add(request)
            }
            logger.debug(
                "Posted notification service=\(event.service.rawValue, privacy: .public) type=\(event.type.rawValue, privacy: .public)."
            )
        } catch {
            logger.error(
                "Failed to post notification service=\(event.service.rawValue, privacy: .public) type=\(event.type.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
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
}
