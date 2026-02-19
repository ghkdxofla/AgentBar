import XCTest
import AppKit
import SwiftUI
@testable import AgentBar

@MainActor
final class SettingsViewBehaviorTests: XCTestCase {
    func testCanSaveTokenAllowsMaskedPrefixWhenContainsRealCharacters() {
        XCTAssertTrue(SettingsView.canSaveToken("***real-token***"))
        XCTAssertTrue(SettingsView.canSaveToken("  token-with-space-trim  "))
    }

    func testTokenSaveAlertIDIncludesFailureMessage() {
        let saved = SettingsView.TokenSaveAlert.saved
        let failed = SettingsView.TokenSaveAlert.saveFailed("Keychain unavailable")

        XCTAssertEqual(saved.id, "saved")
        XCTAssertEqual(failed.id, "saveFailed:Keychain unavailable")
    }

    func testSettingsViewBodyBuildsWithoutCrashing() {
        let view = SettingsView(keychainSaveAction: { _, _ in })
        let body = view.body
        let mirror = Mirror(reflecting: body)

        XCTAssertFalse(
            mirror.children.isEmpty,
            "Expected SettingsView.body to build a non-empty view hierarchy."
        )
    }

    func testSettingsTabSupportsHistoryCase() {
        XCTAssertEqual(SettingsTab.history, .history)
    }
}
