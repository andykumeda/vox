import XCTest
@testable import vox

final class SettingsWindowTests: XCTestCase {
    func testSharedSavePersistsAllEnteredKeysAndPreservesBlankKeys() {
        var saved: [String: String] = [:]
        let message = APIKeySettingsSaver.save([
            ("OpenAI", "  test-openai\n", { saved["OpenAI"] = $0 }),
            ("OpenRouter", "test-openrouter", { saved["OpenRouter"] = $0 }),
            ("Deepgram", "test-deepgram", { saved["Deepgram"] = $0 }),
        ])
        XCTAssertEqual(saved, ["OpenAI": "test-openai", "OpenRouter": "test-openrouter", "Deepgram": "test-deepgram"])
        XCTAssertEqual(message, "Saved: OpenAI, OpenRouter, Deepgram.")
        let emptyMessage = APIKeySettingsSaver.save([
            ("OpenAI", " \n", { _ in XCTFail("Blank input must not overwrite an existing key") }),
        ])
        XCTAssertEqual(emptyMessage, "No API keys to save.")
    }

    func testSharedSaveReportsPartialFailureAndStillSavesRemainingKeys() {
        struct SaveFailure: Error {}
        var deepgramSaved = false
        let message = APIKeySettingsSaver.save([
            ("OpenAI", "test-openai", { _ in }),
            ("OpenRouter", "test-openrouter", { _ in throw SaveFailure() }),
            ("Deepgram", "test-deepgram", { _ in deepgramSaved = true }),
        ])
        XCTAssertTrue(deepgramSaved)
        XCTAssertEqual(message, "Saved: OpenAI, Deepgram. Couldn’t save: OpenRouter. Try again.")
    }

    func testOnlyExplicitUserRoutesMayOpenSettings() {
        XCTAssertTrue(MainWindowController.allowsSettingsNavigation(from: .statusMenu))
        XCTAssertTrue(MainWindowController.allowsSettingsNavigation(from: .sidebar))
        XCTAssertFalse(MainWindowController.allowsSettingsNavigation(from: .launch))
        XCTAssertFalse(MainWindowController.allowsSettingsNavigation(from: .programmatic))
    }

    @MainActor
    func testMainSidebarListsPersonalizationAfterSettings() {
        XCTAssertEqual(
            SidebarItem.allCases,
            [.home, .meeting, .settings, .personalization, .help]
        )
        XCTAssertEqual(SidebarItem.personalization.label, "Personalization")
        XCTAssertEqual(
            PersonalizationDestination.allCases,
            [.dictionary, .customInstructions]
        )
    }

    @MainActor
    func testSelectingSettingsRoutesToGeneralSettingsDestination() {
        let selection = SidebarSelection()
        selection.selectSidebarItem(.personalization)

        selection.selectSidebarItem(.settings)

        XCTAssertEqual(selection.current, .settings)
    }

    func testRecordingStorageUsageFormatsBothCategoriesFromSnapshot() {
        let usage = RecordingStorageUsage(
            dictationBytes: 2_048,
            meetingBytes: 8_192
        )

        let line = usage.formatted { "\($0) bytes" }

        XCTAssertEqual(
            line,
            "On disk now: 2048 bytes dictation, 8192 bytes meetings."
        )
    }

    func testSoundPickerCatalogListsNoneThenSystemAlerts() {
        XCTAssertEqual(SystemAlertSound.allCases.first?.displayName, "None")
        XCTAssertTrue(SystemAlertSound.allCases.contains(.tink))
        XCTAssertTrue(SystemAlertSound.allCases.contains(.pop))
        XCTAssertTrue(SystemAlertSound.allCases.contains(.funk))
        XCTAssertEqual(SystemAlertSound.tink.displayName, "Tink")
        XCTAssertEqual(SystemAlertSound.none.fileURL, nil)
        XCTAssertEqual(
            SystemAlertSound.tink.fileURL?.path,
            "/System/Library/Sounds/Tink.aiff"
        )
    }
}
