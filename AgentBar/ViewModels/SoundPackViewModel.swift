#if AGENTBAR_NOTIFICATION_SOUNDS
import Foundation
import SwiftUI

@MainActor
final class SoundPackViewModel: ObservableObject {
    @Published var availablePacks: [CESPRegistryPack] = []
    @Published var selectedPackName: String = ""
    @Published var selectedLanguage: String = ""  // "" = All
    @Published var agentOverrides: [String: String] = [:]  // keychainAccount → packName
    @Published var isLoadingRegistry = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var errorMessage: String?

    /// Agents that can send notifications and support per-agent sound overrides.
    static let overridableAgents: [ServiceType] = [.claude, .codex, .opencode]

    private let registryService: CESPRegistryService
    private let downloadService: CESPPackDownloadService
    private let defaults: UserDefaults

    init(
        registryService: CESPRegistryService = .shared,
        downloadService: CESPPackDownloadService = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.registryService = registryService
        self.downloadService = downloadService
        self.defaults = defaults
        self.selectedPackName = defaults.string(forKey: "notificationSoundPackName") ?? ""
        loadAgentOverrides()
    }

    // MARK: - Computed

    var availableLanguages: [String] {
        var langs = Set<String>()
        for pack in availablePacks {
            guard let language = pack.language else { continue }
            for code in language.split(separator: ",") {
                let trimmed = code.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { langs.insert(trimmed) }
            }
        }
        return langs.sorted()
    }

    var filteredPacks: [CESPRegistryPack] {
        guard !selectedLanguage.isEmpty else { return availablePacks }
        return availablePacks.filter { pack in
            guard let language = pack.language else { return false }
            return language.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .contains(selectedLanguage)
        }
    }

    /// Uppercase display label for a language code (e.g. "en" → "EN", "zh-CN" → "ZH-CN").
    nonisolated static func displayLanguage(_ code: String) -> String {
        code.uppercased()
    }

    // MARK: - Registry

    func loadRegistry(forceRefresh: Bool = false) async {
        isLoadingRegistry = true
        errorMessage = nil

        do {
            let packs = try await registryService.fetchPacks(forceRefresh: forceRefresh)
            availablePacks = packs
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingRegistry = false
    }

    // MARK: - Global Pack

    func selectPack(_ name: String) {
        guard !name.isEmpty else {
            // "None" selected — clear pack
            selectedPackName = ""
            defaults.set("", forKey: "notificationSoundPackPath")
            defaults.set("", forKey: "notificationSoundPackName")
            NotifySoundManager.shared.unloadPack()
            return
        }

        guard let pack = availablePacks.first(where: { $0.name == name }) else { return }

        Task {
            // Check if already installed
            let installed = await downloadService.isPackInstalled(name)
            if installed {
                await activatePack(pack)
                return
            }

            // Download
            isDownloading = true
            downloadProgress = 0
            errorMessage = nil

            do {
                let path = try await downloadService.downloadPack(pack) { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress = progress
                    }
                }
                await activatePack(pack, path: path)
            } catch {
                errorMessage = error.localizedDescription
                selectedPackName = defaults.string(forKey: "notificationSoundPackName") ?? ""
            }

            isDownloading = false
        }
    }

    // MARK: - Agent Override

    func selectAgentPack(_ service: ServiceType, name: String) {
        let account = service.keychainAccount
        let nameKey = "notificationSoundPackName_\(account)"
        let pathKey = "notificationSoundPackPath_\(account)"

        if name.isEmpty {
            // "Default" — use global pack; remove override
            agentOverrides.removeValue(forKey: account)
            defaults.removeObject(forKey: nameKey)
            defaults.removeObject(forKey: pathKey)
            return
        }

        if name == "__none__" {
            // "None" — no custom sound for this agent
            agentOverrides[account] = "__none__"
            defaults.set("__none__", forKey: nameKey)
            defaults.set("", forKey: pathKey)
            return
        }

        guard let pack = availablePacks.first(where: { $0.name == name }) else { return }

        agentOverrides[account] = name

        Task {
            let installed = await downloadService.isPackInstalled(name)
            if installed {
                await activateAgentPack(pack, service: service)
                return
            }

            isDownloading = true
            downloadProgress = 0
            errorMessage = nil

            do {
                let path = try await downloadService.downloadPack(pack) { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress = progress
                    }
                }
                await activateAgentPack(pack, service: service, path: path)
            } catch {
                errorMessage = error.localizedDescription
                // Revert to previous value
                loadAgentOverride(for: service)
            }

            isDownloading = false
        }
    }

    // MARK: - Private

    private func activatePack(_ pack: CESPRegistryPack, path: String? = nil) async {
        let resolvedPath: String
        if let path {
            resolvedPath = path
        } else {
            resolvedPath = await downloadService.installedPackPath(pack.name)
        }
        let loaded = NotifySoundManager.shared.loadPack(from: resolvedPath)
        if loaded {
            selectedPackName = pack.name
            defaults.set(resolvedPath, forKey: "notificationSoundPackPath")
            defaults.set(pack.name, forKey: "notificationSoundPackName")
        } else {
            errorMessage = "Failed to load sound pack."
        }
    }

    private func activateAgentPack(_ pack: CESPRegistryPack, service: ServiceType, path: String? = nil) async {
        let resolvedPath: String
        if let path {
            resolvedPath = path
        } else {
            resolvedPath = await downloadService.installedPackPath(pack.name)
        }

        let account = service.keychainAccount
        agentOverrides[account] = pack.name
        defaults.set(pack.name, forKey: "notificationSoundPackName_\(account)")
        defaults.set(resolvedPath, forKey: "notificationSoundPackPath_\(account)")
    }

    private func loadAgentOverrides() {
        for service in Self.overridableAgents {
            loadAgentOverride(for: service)
        }
    }

    private func loadAgentOverride(for service: ServiceType) {
        let account = service.keychainAccount
        let nameKey = "notificationSoundPackName_\(account)"
        if let name = defaults.string(forKey: nameKey) {
            agentOverrides[account] = name
        } else {
            agentOverrides.removeValue(forKey: account)
        }
    }
}
#endif
