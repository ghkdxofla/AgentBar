import XCTest
import AppKit
@testable import AgentBar

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
    func testShowCreatesSettingsWindowWithExpectedConfiguration() {
        closeSettingsWindows()
        SettingsWindowController.shared.show()

        guard let window = settingsWindow() else {
            XCTFail("Expected Settings window to exist after show().")
            return
        }

        XCTAssertEqual(window.title, "AgentBar Settings")
        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertNotNil(window.contentViewController)
        closeSettingsWindows()
    }

    func testShowReusesSingleSettingsWindowInstance() {
        closeSettingsWindows()
        SettingsWindowController.shared.show()
        let first = settingsWindow()

        SettingsWindowController.shared.show()
        let second = settingsWindow()

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertTrue(first === second)
        closeSettingsWindows()
    }

    private func closeSettingsWindows() {
        for window in NSApp.windows where window.title == "AgentBar Settings" {
            window.close()
        }
    }

    private func settingsWindow() -> NSWindow? {
        NSApp.windows.first(where: { $0.title == "AgentBar Settings" })
    }
}
