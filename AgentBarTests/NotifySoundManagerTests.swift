import XCTest
@testable import AgentBar

final class NotifySoundManagerTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testLoadPackParsesManifest() throws {
        let manifest = """
        {
          "name": "Test Pack",
          "sounds": {
            "task.complete": ["complete1.wav", "complete2.wav"],
            "input.required": ["input1.wav"]
          }
        }
        """
        try manifest.write(
            to: tempDir.appendingPathComponent("openpeon.json"),
            atomically: true,
            encoding: .utf8
        )

        let suiteName = "AgentBarTests.SoundManager.LoadPack.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = NotifySoundManager(defaults: defaults)
        let result = manager.loadPack(from: tempDir.path)

        XCTAssertTrue(result)
        XCTAssertEqual(manager.packName, "Test Pack")
        XCTAssertTrue(manager.isPackLoaded)
    }

    func testLoadPackReturnsFalseForMissingManifest() {
        let suiteName = "AgentBarTests.SoundManager.MissingManifest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = NotifySoundManager(defaults: defaults)
        let result = manager.loadPack(from: tempDir.path)

        XCTAssertFalse(result)
        XCTAssertFalse(manager.isPackLoaded)
    }

    func testLoadPackReturnsFalseForInvalidJSON() throws {
        try "not json".write(
            to: tempDir.appendingPathComponent("openpeon.json"),
            atomically: true,
            encoding: .utf8
        )

        let suiteName = "AgentBarTests.SoundManager.InvalidJSON.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = NotifySoundManager(defaults: defaults)
        let result = manager.loadPack(from: tempDir.path)

        XCTAssertFalse(result)
        XCTAssertFalse(manager.isPackLoaded)
    }

    func testUnloadPackClearsState() throws {
        let manifest = """
        {"name": "Test", "sounds": {"task.complete": ["a.wav"]}}
        """
        try manifest.write(
            to: tempDir.appendingPathComponent("openpeon.json"),
            atomically: true,
            encoding: .utf8
        )

        let suiteName = "AgentBarTests.SoundManager.Unload.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = NotifySoundManager(defaults: defaults)
        _ = manager.loadPack(from: tempDir.path)
        XCTAssertTrue(manager.isPackLoaded)

        manager.unloadPack()
        XCTAssertFalse(manager.isPackLoaded)
        XCTAssertNil(manager.packName)
    }

    func testCESPCategoryMapping() {
        XCTAssertEqual(NotifySoundManager.cespCategory(for: .taskCompleted), "task.complete")
        XCTAssertEqual(NotifySoundManager.cespCategory(for: .permissionRequired), "input.required")
        XCTAssertEqual(NotifySoundManager.cespCategory(for: .decisionRequired), "input.required")
    }

    func testPlayReturnsFalseWhenNoPackConfigured() {
        let suiteName = "AgentBarTests.SoundManager.NoPack.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = NotifySoundManager(defaults: defaults)
        let result = manager.play(for: .taskCompleted)
        XCTAssertFalse(result)
    }

    func testPlayReturnsFalseWhenCategoryDisabled() throws {
        let manifest = """
        {"name": "Test", "sounds": {"task.complete": ["a.wav"]}}
        """
        try manifest.write(
            to: tempDir.appendingPathComponent("openpeon.json"),
            atomically: true,
            encoding: .utf8
        )

        let suiteName = "AgentBarTests.SoundManager.Disabled.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(tempDir.path, forKey: "notificationSoundPackPath")
        defaults.set(false, forKey: "notificationSoundTaskCompleteEnabled")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = NotifySoundManager(defaults: defaults)
        _ = manager.loadPack(from: tempDir.path)

        let result = manager.play(for: .taskCompleted)
        XCTAssertFalse(result)
    }

    func testPlayReturnsFalseWhenCategoryHasNoSounds() throws {
        let manifest = """
        {"name": "Test", "sounds": {"task.complete": []}}
        """
        try manifest.write(
            to: tempDir.appendingPathComponent("openpeon.json"),
            atomically: true,
            encoding: .utf8
        )

        let suiteName = "AgentBarTests.SoundManager.EmptyCategory.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(tempDir.path, forKey: "notificationSoundPackPath")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = NotifySoundManager(defaults: defaults)
        _ = manager.loadPack(from: tempDir.path)

        let result = manager.play(for: .taskCompleted)
        XCTAssertFalse(result)
    }

    func testCESPCategoryMatchesEventTypeProperty() {
        for eventType in AgentNotifyEventType.allCases {
            XCTAssertEqual(
                NotifySoundManager.cespCategory(for: eventType),
                eventType.cespCategory
            )
        }
    }

    func testAutoRestoresPersistedPackOnInit() throws {
        let manifest = """
        {"name": "Persisted Pack", "sounds": {"task.complete": ["a.wav"]}}
        """
        try manifest.write(
            to: tempDir.appendingPathComponent("openpeon.json"),
            atomically: true,
            encoding: .utf8
        )

        let suiteName = "AgentBarTests.SoundManager.AutoRestore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(tempDir.path, forKey: "notificationSoundPackPath")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = NotifySoundManager(defaults: defaults)

        XCTAssertTrue(manager.isPackLoaded)
        XCTAssertEqual(manager.packName, "Persisted Pack")
    }

    func testDoesNotCrashOnInitWithInvalidPersistedPath() {
        let suiteName = "AgentBarTests.SoundManager.InvalidPath.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("/nonexistent/path/to/pack", forKey: "notificationSoundPackPath")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = NotifySoundManager(defaults: defaults)

        XCTAssertFalse(manager.isPackLoaded)
        XCTAssertNil(manager.packName)
    }
}
