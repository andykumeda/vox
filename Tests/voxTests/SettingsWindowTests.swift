import XCTest
@testable import vox

final class SettingsWindowTests: XCTestCase {
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
    func testSelectingDictionaryRoutesThroughPersonalization() {
        let selection = SidebarSelection()

        selection.selectDictionary()

        XCTAssertEqual(selection.current, .personalization)
        XCTAssertEqual(selection.personalizationDestination, .dictionary)
    }

    @MainActor
    func testSelectingSettingsRoutesToGeneralSettingsDestination() {
        let selection = SidebarSelection()
        selection.selectDictionary()

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
}
