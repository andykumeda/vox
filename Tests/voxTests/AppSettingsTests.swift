import XCTest
@testable import vox

final class AppSettingsTests: XCTestCase {
    func testIgnoreRecordHotkeyDefaultsOffAndPersists() {
        AppSettings.ignoreRecordHotkey = false
        XCTAssertFalse(AppSettings.ignoreRecordHotkey)

        AppSettings.ignoreRecordHotkey = true
        XCTAssertTrue(AppSettings.ignoreRecordHotkey)

        AppSettings.ignoreRecordHotkey = false
    }
}
