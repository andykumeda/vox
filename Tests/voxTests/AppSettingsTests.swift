import XCTest
@testable import vox

final class AppSettingsTests: XCTestCase {
    func testTranscriptionModelDefaultsToFullQualityModel() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "transcriptionModel")
        defer {
            if let previous {
                defaults.set(previous, forKey: "transcriptionModel")
            } else {
                defaults.removeObject(forKey: "transcriptionModel")
            }
        }

        defaults.removeObject(forKey: "transcriptionModel")

        XCTAssertEqual(AppSettings.transcriptionModel, .full)
    }

    func testIgnoreRecordHotkeyDefaultsOffAndPersists() {
        AppSettings.ignoreRecordHotkey = false
        XCTAssertFalse(AppSettings.ignoreRecordHotkey)

        AppSettings.ignoreRecordHotkey = true
        XCTAssertTrue(AppSettings.ignoreRecordHotkey)

        AppSettings.ignoreRecordHotkey = false
    }
}
