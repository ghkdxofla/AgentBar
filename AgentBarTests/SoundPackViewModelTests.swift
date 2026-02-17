#if AGENTBAR_NOTIFICATION_SOUNDS
import XCTest
@testable import AgentBar

@MainActor
final class SoundPackViewModelTests: XCTestCase {
    nonisolated(unsafe) private var suiteName: String!
    nonisolated(unsafe) private var defaults: UserDefaults!
    nonisolated(unsafe) private var cleanupPackDirectories: [URL] = []

    override func setUp() {
        super.setUp()
        suiteName = "AgentBarTests.SoundPackViewModel.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        SoundPackViewModelMockURLProtocol.reset()
    }

    override func tearDown() {
        for directory in cleanupPackDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        cleanupPackDirectories.removeAll()
        defaults.removePersistentDomain(forName: suiteName)
        SoundPackViewModelMockURLProtocol.reset()
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testInitLoadsPersistedSelectedPackAndAgentOverrides() {
        defaults.set("global-pack", forKey: "notificationSoundPackName")
        defaults.set("claude-pack", forKey: "notificationSoundPackName_\(ServiceType.claude.keychainAccount)")

        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.selectedPackName, "global-pack")
        XCTAssertEqual(viewModel.agentOverrides[ServiceType.claude.keychainAccount], "claude-pack")
        XCTAssertNil(viewModel.agentOverrides[ServiceType.codex.keychainAccount])
    }

    func testAvailableLanguagesAndFilteredPacks() {
        let viewModel = makeViewModel()
        viewModel.availablePacks = [
            makePack(name: "multi", language: "en, ru"),
            makePack(name: "de-only", language: "de"),
            makePack(name: "none", language: nil)
        ]

        XCTAssertEqual(viewModel.availableLanguages, ["de", "en", "ru"])

        viewModel.selectedLanguage = "ru"
        XCTAssertEqual(viewModel.filteredPacks.map(\.name), ["multi"])

        viewModel.selectedLanguage = ""
        XCTAssertEqual(viewModel.filteredPacks.count, 3)
    }

    func testLoadRegistrySuccessPopulatesAvailablePacks() async {
        SoundPackViewModelMockURLProtocol.responseProvider = { _ in
            (
                200,
                Data(
                    """
                    {
                      "packs": [
                        {
                          "name": "pack-a",
                          "display_name": "Pack A",
                          "source_repo": "peonping/pack-a",
                          "source_ref": "main",
                          "source_path": "pack",
                          "language": "en"
                        }
                      ]
                    }
                    """.utf8
                )
            )
        }

        let viewModel = makeViewModel()
        viewModel.errorMessage = "old-error"
        await viewModel.loadRegistry()

        XCTAssertFalse(viewModel.isLoadingRegistry)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.availablePacks.map(\.name), ["pack-a"])
        XCTAssertEqual(SoundPackViewModelMockURLProtocol.requestCount, 1)
    }

    func testLoadRegistryFailureStoresLocalizedError() async {
        SoundPackViewModelMockURLProtocol.responseProvider = { _ in
            (500, Data())
        }

        let viewModel = makeViewModel()
        await viewModel.loadRegistry()

        XCTAssertFalse(viewModel.isLoadingRegistry)
        XCTAssertEqual(viewModel.availablePacks.count, 0)
        XCTAssertEqual(viewModel.errorMessage, CESPRegistryError.fetchFailed.localizedDescription)
    }

    func testSelectPackNoneClearsPersistedPack() {
        defaults.set("/tmp/old-pack", forKey: "notificationSoundPackPath")
        defaults.set("old-pack", forKey: "notificationSoundPackName")

        let viewModel = makeViewModel()
        viewModel.selectPack("")

        XCTAssertEqual(viewModel.selectedPackName, "")
        XCTAssertEqual(defaults.string(forKey: "notificationSoundPackPath"), "")
        XCTAssertEqual(defaults.string(forKey: "notificationSoundPackName"), "")
    }

    func testSelectAgentPackDefaultClearsOverride() {
        let account = ServiceType.claude.keychainAccount
        defaults.set("custom-pack", forKey: "notificationSoundPackName_\(account)")
        defaults.set("/tmp/custom-pack", forKey: "notificationSoundPackPath_\(account)")

        let viewModel = makeViewModel()
        viewModel.selectAgentPack(.claude, name: "")

        XCTAssertNil(viewModel.agentOverrides[account])
        XCTAssertNil(defaults.object(forKey: "notificationSoundPackName_\(account)"))
        XCTAssertNil(defaults.object(forKey: "notificationSoundPackPath_\(account)"))
    }

    func testSelectAgentPackNoneStoresSentinel() {
        let account = ServiceType.codex.keychainAccount
        let viewModel = makeViewModel()

        viewModel.selectAgentPack(.codex, name: "__none__")

        XCTAssertEqual(viewModel.agentOverrides[account], "__none__")
        XCTAssertEqual(defaults.string(forKey: "notificationSoundPackName_\(account)"), "__none__")
        XCTAssertEqual(defaults.string(forKey: "notificationSoundPackPath_\(account)"), "")
    }

    func testSelectPackDownloadsAndActivatesPack() async throws {
        SoundPackViewModelMockURLProtocol.responseProvider = { request in
            let url = request.url!.absoluteString
            if url.hasSuffix("openpeon.json") {
                return (
                    200,
                    Data(
                        """
                        {
                          "name": "downloaded-pack",
                          "sounds": {
                            "task.complete": []
                          }
                        }
                        """.utf8
                    )
                )
            }
            return (404, Data())
        }

        let packName = "downloaded-\(UUID().uuidString)"
        cleanupPackDirectories.append(packsRoot.appendingPathComponent(packName))

        let viewModel = makeViewModel()
        viewModel.availablePacks = [makePack(name: packName, language: "en")]

        viewModel.selectPack(packName)
        await waitUntil {
            self.defaults.string(forKey: "notificationSoundPackName") == packName && !viewModel.isDownloading
        }

        XCTAssertEqual(viewModel.selectedPackName, packName)
        XCTAssertEqual(defaults.string(forKey: "notificationSoundPackName"), packName)
        XCTAssertNotNil(defaults.string(forKey: "notificationSoundPackPath"))
        XCTAssertNil(viewModel.errorMessage)
    }

    func testSelectAgentPackUsesInstalledPackWithoutDownload() async throws {
        let packName = "installed-\(UUID().uuidString)"
        let packDir = try createInstalledPack(named: packName)
        cleanupPackDirectories.append(packDir)

        let account = ServiceType.claude.keychainAccount
        let viewModel = makeViewModel()
        viewModel.availablePacks = [makePack(name: packName, language: "en")]

        viewModel.selectAgentPack(.claude, name: packName)
        await waitUntil {
            self.defaults.string(forKey: "notificationSoundPackName_\(account)") == packName
        }

        XCTAssertEqual(viewModel.agentOverrides[account], packName)
        XCTAssertEqual(defaults.string(forKey: "notificationSoundPackName_\(account)"), packName)
        XCTAssertEqual(defaults.string(forKey: "notificationSoundPackPath_\(account)"), packDir.path)
    }

    private func makeViewModel() -> SoundPackViewModel {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SoundPackViewModelMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let registryService = CESPRegistryService(session: session)
        let downloadService = CESPPackDownloadService(session: session)

        return SoundPackViewModel(
            registryService: registryService,
            downloadService: downloadService,
            defaults: defaults
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2.0,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for async SoundPackViewModel update.")
    }

    private func createInstalledPack(named packName: String) throws -> URL {
        let directory = packsRoot.appendingPathComponent(packName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifestURL = directory.appendingPathComponent("openpeon.json")
        try Data(
            """
            {
              "name": "\(packName)",
              "sounds": {
                "task.complete": []
              }
            }
            """.utf8
        ).write(to: manifestURL)
        return directory
    }

    private var packsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openpeon/packs")
    }

    private func makePack(name: String, language: String?) -> CESPRegistryPack {
        CESPRegistryPack(
            name: name,
            display_name: "Pack \(name)",
            description: nil,
            source_repo: "peonping/\(name)",
            source_ref: "main",
            source_path: "pack",
            sound_count: 1,
            total_size_bytes: 100,
            language: language,
            trust_tier: nil,
            tags: nil
        )
    }
}

private final class SoundPackViewModelMockURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) static var requestCount: Int = 0
    nonisolated(unsafe) static var responseProvider: ((URLRequest) -> (statusCode: Int, data: Data))?

    static func reset() {
        lock.lock()
        requestCount = 0
        responseProvider = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let responseTuple: (statusCode: Int, data: Data)

        Self.lock.lock()
        Self.requestCount += 1
        responseTuple = Self.responseProvider?(request) ?? (500, Data())
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: responseTuple.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseTuple.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
#endif
