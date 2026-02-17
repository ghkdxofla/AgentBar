#if AGENTBAR_NOTIFICATION_SOUNDS
import Foundation
import SwiftUI

@MainActor
final class SoundPackViewModel: ObservableObject {
    @Published var availablePacks: [CESPRegistryPack] = []
    @Published var selectedPackName: String = ""
    @Published var isLoadingRegistry = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var errorMessage: String?

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
    }

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
}
#endif
