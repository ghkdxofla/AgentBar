import Foundation
import AVFoundation

struct CESPManifest: Decodable, Sendable {
    let name: String?
    let sounds: [String: [String]]?
}

final class AlertSoundManager: @unchecked Sendable {
    static let shared = AlertSoundManager()

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
        guard let path = defaults.string(forKey: "alertSoundPackPath"),
              !path.isEmpty else { return }
        _ = loadPack(from: path)
    }

    var packName: String? {
        lock.lock()
        defer { lock.unlock() }
        return manifest?.name
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

    static func cespCategory(for eventType: AgentAlertEventType) -> String {
        switch eventType {
        case .taskCompleted:
            return "task.complete"
        case .permissionRequired, .decisionRequired:
            return "input.required"
        }
    }

    func play(for eventType: AgentAlertEventType) -> Bool {
        let category = Self.cespCategory(for: eventType)

        guard isCategoryEnabled(category) else { return false }

        guard let packPath = defaults.string(forKey: "alertSoundPackPath"),
              !packPath.isEmpty else {
            return false
        }

        lock.lock()
        guard let sounds = manifest?.sounds?[category], !sounds.isEmpty else {
            lock.unlock()
            return false
        }

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
            let volume = defaults.object(forKey: "alertSoundVolume") != nil
                ? Float(defaults.double(forKey: "alertSoundVolume"))
                : 0.7
            audioPlayer.volume = volume
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
        guard let packPath = defaults.string(forKey: "alertSoundPackPath"),
              !packPath.isEmpty else {
            return false
        }

        lock.lock()
        guard let sounds = manifest?.sounds?[category], !sounds.isEmpty,
              let chosen = sounds.randomElement() else {
            lock.unlock()
            return false
        }
        lock.unlock()

        let soundURL = URL(fileURLWithPath: packPath)
            .appendingPathComponent(chosen)

        guard fileManager.fileExists(atPath: soundURL.path) else { return false }

        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
            let volume = defaults.object(forKey: "alertSoundVolume") != nil
                ? Float(defaults.double(forKey: "alertSoundVolume"))
                : 0.7
            audioPlayer.volume = volume
            audioPlayer.play()

            lock.lock()
            player = audioPlayer
            lock.unlock()
            return true
        } catch {
            return false
        }
    }

    private func isCategoryEnabled(_ category: String) -> Bool {
        let key: String
        switch category {
        case "task.complete":
            key = "alertSoundTaskCompleteEnabled"
        case "input.required":
            key = "alertSoundInputRequiredEnabled"
        default:
            return false
        }
        guard defaults.object(forKey: key) != nil else { return true }
        return defaults.bool(forKey: key)
    }

    private func loadLastPlayedState() {
        if let saved = defaults.dictionary(forKey: "alertSoundLastPlayed") as? [String: String] {
            lock.lock()
            lastPlayedPerCategory = saved
            lock.unlock()
        }
    }

    private func saveLastPlayedState() {
        lock.lock()
        let state = lastPlayedPerCategory
        lock.unlock()
        defaults.set(state, forKey: "alertSoundLastPlayed")
    }
}
