#if AGENTBAR_NOTIFICATION_SOUNDS
import Foundation
import AVFoundation

struct CESPSoundEntry: Decodable, Sendable, Equatable {
    let file: String
    let label: String?
}

struct CESPCategoryEntry: Decodable, Sendable {
    let sounds: [CESPSoundEntry]
}

struct CESPManifest: Decodable, Sendable {
    let cesp_version: String?
    let name: String?
    let display_name: String?
    let categories: [String: CESPCategoryEntry]?
    let sounds: [String: [String]]?

    func soundFiles(for category: String) -> [String] {
        if let cat = categories?[category] {
            return cat.sounds.map(\.file)
        }
        return sounds?[category] ?? []
    }
}

final class NotifySoundManager: @unchecked Sendable {
    static let shared = NotifySoundManager()

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private var player: AVAudioPlayer?
    private var manifest: CESPManifest?
    private var lastPlayedPerCategory: [String: String] = [:]
    private let lock = NSLock()

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        loadLastPlayedState()
        restorePersistedPack()
    }

    private func restorePersistedPack() {
        guard let path = defaults.string(forKey: "notificationSoundPackPath"),
              !path.isEmpty else { return }
        _ = loadPack(from: path)
    }

    var packName: String? {
        lock.lock()
        defer { lock.unlock() }
        return manifest?.display_name ?? manifest?.name
    }

    var isPackLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return manifest != nil
    }

    func loadPack(from directoryPath: String) -> Bool {
        let manifestURL = URL(fileURLWithPath: directoryPath)
            .appendingPathComponent("openpeon.json")

        guard fileManager.fileExists(atPath: manifestURL.path),
              let data = try? Data(contentsOf: manifestURL),
              let parsed = try? JSONDecoder().decode(CESPManifest.self, from: data) else {
            lock.lock()
            manifest = nil
            lock.unlock()
            return false
        }

        lock.lock()
        manifest = parsed
        lock.unlock()
        return true
    }

    func unloadPack() {
        lock.lock()
        manifest = nil
        lastPlayedPerCategory.removeAll()
        lock.unlock()
    }

    static func cespCategory(for eventType: AgentNotifyEventType) -> String {
        eventType.cespCategory
    }

    func play(for eventType: AgentNotifyEventType, service: ServiceType? = nil) -> Bool {
        let category = Self.cespCategory(for: eventType)

        guard let packPath = resolvePackPath(for: service),
              !packPath.isEmpty else {
            return false
        }

        let resolvedManifest = resolveManifest(at: packPath)
        guard let m = resolvedManifest else {
            return false
        }

        let sounds = m.soundFiles(for: category)
        guard !sounds.isEmpty else {
            return false
        }

        lock.lock()
        let lastPlayed = lastPlayedPerCategory[category]
        let candidates: [String]
        if sounds.count > 1, let lastPlayed {
            candidates = sounds.filter { $0 != lastPlayed }
        } else {
            candidates = sounds
        }

        guard let chosen = candidates.randomElement() else {
            lock.unlock()
            return false
        }

        lastPlayedPerCategory[category] = chosen
        lock.unlock()

        saveLastPlayedState()

        let soundURL = URL(fileURLWithPath: packPath)
            .appendingPathComponent(chosen)

        guard fileManager.fileExists(atPath: soundURL.path) else { return false }

        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
            audioPlayer.volume = currentVolume
            audioPlayer.play()

            lock.lock()
            player = audioPlayer
            lock.unlock()
            return true
        } catch {
            return false
        }
    }

    func playTest(category: String) -> Bool {
        guard let packPath = defaults.string(forKey: "notificationSoundPackPath"),
              !packPath.isEmpty else {
            return false
        }

        lock.lock()
        guard let m = manifest else {
            lock.unlock()
            return false
        }
        let sounds = m.soundFiles(for: category)
        guard !sounds.isEmpty, let chosen = sounds.randomElement() else {
            lock.unlock()
            return false
        }
        lock.unlock()

        let soundURL = URL(fileURLWithPath: packPath)
            .appendingPathComponent(chosen)

        guard fileManager.fileExists(atPath: soundURL.path) else { return false }

        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
            audioPlayer.volume = currentVolume
            audioPlayer.play()

            lock.lock()
            player = audioPlayer
            lock.unlock()
            return true
        } catch {
            return false
        }
    }

    private var currentVolume: Float {
        defaults.object(forKey: "notificationSoundVolume") != nil
            ? Float(defaults.double(forKey: "notificationSoundVolume"))
            : 0.7
    }

    private func resolvePackPath(for service: ServiceType?) -> String? {
        if let service {
            let agentNameKey = "notificationSoundPackName_\(service.keychainAccount)"
            if let agentName = defaults.string(forKey: agentNameKey) {
                // "__none__" means no custom sound for this agent
                if agentName == "__none__" { return nil }
                // Use agent-specific path
                let agentPathKey = "notificationSoundPackPath_\(service.keychainAccount)"
                return defaults.string(forKey: agentPathKey)
            }
            // No override set → fall through to global
        }
        return defaults.string(forKey: "notificationSoundPackPath")
    }

    private var manifestCache: [String: CESPManifest] = [:]

    private func resolveManifest(at packPath: String) -> CESPManifest? {
        lock.lock()
        if let cached = manifestCache[packPath] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let manifestURL = URL(fileURLWithPath: packPath)
            .appendingPathComponent("openpeon.json")

        guard fileManager.fileExists(atPath: manifestURL.path),
              let data = try? Data(contentsOf: manifestURL),
              let parsed = try? JSONDecoder().decode(CESPManifest.self, from: data) else {
            return nil
        }

        lock.lock()
        manifestCache[packPath] = parsed
        lock.unlock()
        return parsed
    }

    private func loadLastPlayedState() {
        if let saved = defaults.dictionary(forKey: "notificationSoundLastPlayed") as? [String: String] {
            lock.lock()
            lastPlayedPerCategory = saved
            lock.unlock()
        }
    }

    private func saveLastPlayedState() {
        lock.lock()
        let state = lastPlayedPerCategory
        lock.unlock()
        defaults.set(state, forKey: "notificationSoundLastPlayed")
    }
}

#else

import Foundation

final class NotifySoundManager: @unchecked Sendable {
    static let shared = NotifySoundManager()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
    }

    var packName: String? { nil }
    var isPackLoaded: Bool { false }

    func loadPack(from directoryPath: String) -> Bool { false }
    func unloadPack() {}

    static func cespCategory(for eventType: AgentNotifyEventType) -> String {
        eventType.cespCategory
    }

    func play(for eventType: AgentNotifyEventType, service: ServiceType? = nil) -> Bool { false }
    func playTest(category: String) -> Bool { false }
}

struct CESPManifest: Decodable, Sendable {
    let name: String?
    let sounds: [String: [String]]?
}

#endif
