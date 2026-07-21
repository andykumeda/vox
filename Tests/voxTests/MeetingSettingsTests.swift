import XCTest
@testable import vox

final class MeetingSettingsTests: XCTestCase {
    private let modeKey = "meetingModeEnabled"
    private let consentKey = "meetingConsentAcknowledged"
    private let remoteControlModeKey = "remoteControlModeEnabled"

    override func setUp() {
        super.setUp()
        clearKeys()
    }

    override func tearDown() {
        clearKeys()
        super.tearDown()
    }

    private func clearKeys() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: modeKey)
        defaults.removeObject(forKey: consentKey)
        defaults.removeObject(forKey: remoteControlModeKey)
    }

    func testMeetingModeDefaultsOff() {
        XCTAssertFalse(AppSettings.meetingModeEnabled)
    }

    func testMeetingConsentDefaultsFalse() {
        XCTAssertFalse(AppSettings.meetingConsentAcknowledged)
    }

    func testRemoteControlModeDefaultsOff() {
        XCTAssertFalse(AppSettings.remoteControlModeEnabled)
    }

    func testRemoteControlModeRoundTrip() {
        AppSettings.remoteControlModeEnabled = true
        XCTAssertTrue(AppSettings.remoteControlModeEnabled)
        AppSettings.remoteControlModeEnabled = false
        XCTAssertFalse(AppSettings.remoteControlModeEnabled)
    }

    func testMeetingFlagsRoundTrip() {
        AppSettings.meetingModeEnabled = true
        AppSettings.meetingConsentAcknowledged = true
        XCTAssertTrue(AppSettings.meetingModeEnabled)
        XCTAssertTrue(AppSettings.meetingConsentAcknowledged)
    }

    func testMeetingDefaultsDoNotAlterDictationSettings() {
        // Confirms reading meeting keys does not perturb shared dictation toggles.
        let initialKeep = AppSettings.keepTranscriptionOnClipboard
        let initialMode = AppSettings.modeOverride
        let initialModel = AppSettings.transcriptionModel

        _ = AppSettings.meetingModeEnabled
        _ = AppSettings.meetingConsentAcknowledged
        XCTAssertEqual(AppSettings.keepTranscriptionOnClipboard, initialKeep)
        XCTAssertEqual(AppSettings.modeOverride, initialMode)
        XCTAssertEqual(AppSettings.transcriptionModel, initialModel)
    }
}
