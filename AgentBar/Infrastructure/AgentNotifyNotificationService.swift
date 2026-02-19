import Foundation
import UserNotifications
import os.log
#if AGENTBAR_NOTIFICATION_SOUNDS
import AppKit
#endif

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
    private let postContentOverride: (@Sendable (_ title: String, _ body: String) async throws -> Void)?
    private let authorizationStatusOverride: (@Sendable () async -> Int)?
    private let requestAuthorizationOverride: (@Sendable () async -> Bool)?
    private let addRequestOverride: (@Sendable (UNNotificationRequest) async throws -> Void)?
    private let shouldUseCustomSoundOverride: (@Sendable (AgentNotifyEvent) -> Bool)?
    private let playCustomSoundOverride: (@Sendable (AgentNotifyEvent) -> Bool)?
    private let playFallbackSoundOverride: (@Sendable () -> Void)?
    private var didCheckAuthorization = false

    init(
        center: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard,
        postBodyOverride: (@Sendable (String) async throws -> Void)? = nil,
        postContentOverride: (@Sendable (_ title: String, _ body: String) async throws -> Void)? = nil,
        authorizationStatusOverride: (@Sendable () async -> Int)? = nil,
        requestAuthorizationOverride: (@Sendable () async -> Bool)? = nil,
        addRequestOverride: (@Sendable (UNNotificationRequest) async throws -> Void)? = nil,
        shouldUseCustomSoundOverride: (@Sendable (AgentNotifyEvent) -> Bool)? = nil,
        playCustomSoundOverride: (@Sendable (AgentNotifyEvent) -> Bool)? = nil,
        playFallbackSoundOverride: (@Sendable () -> Void)? = nil
    ) {
        self.center = center
        self.defaults = defaults
        self.postBodyOverride = postBodyOverride
        self.postContentOverride = postContentOverride
        self.authorizationStatusOverride = authorizationStatusOverride
        self.requestAuthorizationOverride = requestAuthorizationOverride
        self.addRequestOverride = addRequestOverride
        self.shouldUseCustomSoundOverride = shouldUseCustomSoundOverride
        self.playCustomSoundOverride = playCustomSoundOverride
        self.playFallbackSoundOverride = playFallbackSoundOverride
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

        let statusRawValue = await currentAuthorizationStatusRawValue()
        guard statusRawValue == UNAuthorizationStatus.notDetermined.rawValue else {
            logger.debug("Authorization status already determined: \(statusRawValue, privacy: .public).")
            return
        }
        let granted = await currentRequestAuthorization()
        logger.info("Notification permission prompt completed. granted=\(granted, privacy: .public).")
    }

    func post(event: AgentNotifyEvent) async {
        let content = UNMutableNotificationContent()
        content.title = event.service.rawValue
        let showMessagePreview = defaults.bool(forKey: "notificationShowMessagePreview", defaultValue: false)
        let detail = showMessagePreview ? event.notificationBody : event.redactedNotificationBody
        content.body = "\(event.type.notificationStatusLabel): \(detail)"
        let soundMode = NotificationSoundMode.resolve(from: defaults)
        var shouldPlayCustomSound = false

        if soundMode == .mute {
            content.sound = nil
        } else {
            #if AGENTBAR_NOTIFICATION_SOUNDS
            shouldPlayCustomSound = shouldUseCustomSound(for: event)
            content.sound = shouldPlayCustomSound ? nil : .default
            #else
            content.sound = .default
            #endif
        }

        let request = UNNotificationRequest(
            identifier: "agentbar-agent-notify-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            if let postContentOverride {
                try await postContentOverride(content.title, content.body)
            } else if let postBodyOverride {
                try await postBodyOverride(content.body)
            } else if let addRequestOverride {
                try await addRequestOverride(request)
            } else {
                try await add(request)
            }
            #if AGENTBAR_NOTIFICATION_SOUNDS
            if shouldPlayCustomSound {
                let didPlayCustomSound = playCustomSound(for: event)
                if !didPlayCustomSound {
                    playFallbackSound()
                    logger.debug(
                        "Custom sound playback failed. Played fallback sound service=\(event.service.rawValue, privacy: .public) type=\(event.type.rawValue, privacy: .public)."
                    )
                }
            }
            #endif
            logger.debug(
                "Posted notification service=\(event.service.rawValue, privacy: .public) type=\(event.type.rawValue, privacy: .public)."
            )
        } catch {
            logger.error(
                "Failed to post notification service=\(event.service.rawValue, privacy: .public) type=\(event.type.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func currentAuthorizationStatusRawValue() async -> Int {
        if let authorizationStatusOverride {
            return await authorizationStatusOverride()
        }
        return await authorizationStatusRawValue()
    }

    private func currentRequestAuthorization() async -> Bool {
        if let requestAuthorizationOverride {
            return await requestAuthorizationOverride()
        }
        return await requestAuthorization()
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

    #if AGENTBAR_NOTIFICATION_SOUNDS
    private func shouldUseCustomSound(for event: AgentNotifyEvent) -> Bool {
        if let shouldUseCustomSoundOverride {
            return shouldUseCustomSoundOverride(event)
        }
        return NotifySoundManager.shared.canPlay(for: event.type, service: event.service)
    }

    private func playCustomSound(for event: AgentNotifyEvent) -> Bool {
        if let playCustomSoundOverride {
            return playCustomSoundOverride(event)
        }
        return NotifySoundManager.shared.play(for: event.type, service: event.service)
    }

    private func playFallbackSound() {
        if let playFallbackSoundOverride {
            playFallbackSoundOverride()
            return
        }
        NSSound.beep()
    }
    #endif
}
