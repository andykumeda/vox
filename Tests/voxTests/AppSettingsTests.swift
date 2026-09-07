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

    func testRecordingSoundsDefaultAndPersist() {
        let defaults = UserDefaults.standard
        let keys = ["startSound", "stopSound", "errorSound"]
        let previous = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for key in keys {
                if let value = previous[key] {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        for key in keys { defaults.removeObject(forKey: key) }

        XCTAssertEqual(AppSettings.startSound, .tink)
        XCTAssertEqual(AppSettings.stopSound, .pop)
        XCTAssertEqual(AppSettings.errorSound, .funk)
        XCTAssertEqual(AppSettings.sound(for: .start), .tink)
        XCTAssertEqual(AppSettings.sound(for: .stop), .pop)
        XCTAssertEqual(AppSettings.sound(for: .error), .funk)

        AppSettings.startSound = .glass
        AppSettings.stopSound = .none
        AppSettings.errorSound = .sosumi

        XCTAssertEqual(AppSettings.startSound, .glass)
        XCTAssertEqual(AppSettings.stopSound, .none)
        XCTAssertEqual(AppSettings.errorSound, .sosumi)
        XCTAssertEqual(AppSettings.sound(for: .start), .glass)
        XCTAssertEqual(AppSettings.sound(for: .stop), .none)
        XCTAssertEqual(AppSettings.sound(for: .error), .sosumi)

        defaults.set("not-a-sound", forKey: "startSound")
        XCTAssertEqual(AppSettings.startSound, .tink)
    }
}
