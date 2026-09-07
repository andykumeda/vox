import AppKit
import XCTest
@testable import vox

final class SoundPlayerTests: XCTestCase {
    func testCatalogIncludesNoneAndDefaultCues() {
        XCTAssertEqual(SystemAlertSound.allCases.first, SystemAlertSound.none)
        XCTAssertEqual(SystemAlertSound.startDefault, .tink)
        XCTAssertEqual(SystemAlertSound.stopDefault, .pop)
        XCTAssertEqual(SystemAlertSound.errorDefault, .funk)
        XCTAssertEqual(SoundCue.start.defaultSound, .tink)
        XCTAssertEqual(SoundCue.stop.defaultSound, .pop)
        XCTAssertEqual(SoundCue.error.defaultSound, .funk)
    }

    func testLoadSoundUsesIndependentFileInstance() {
        let named = NSSound(named: NSSound.Name("Tink"))
        let loaded = SoundPlayer.loadSound(named: "Tink")
        XCTAssertNotNil(named)
        XCTAssertNotNil(loaded)
        XCTAssertFalse(
            loaded === named,
            "Start cues must not share the NSSound(named:) cache; stopping that instance silences later plays."
        )
    }

    func testLoadSoundSkipsNoneAndUnknownNames() {
        XCTAssertNil(SoundPlayer.loadSound(named: SystemAlertSound.none.rawValue))
        XCTAssertNil(SoundPlayer.loadSound(named: ""))
        XCTAssertNil(SoundPlayer.loadSound(named: "NotARealSystemSound"))
    }

    func testPlayNoneDoesNotStartNamedTink() {
        let player = SoundPlayer()
        let tink = NSSound(named: NSSound.Name("Tink"))
        XCTAssertNotNil(tink)
        player.play(SystemAlertSound.none)
        XCTAssertFalse(tink?.isPlaying ?? true)
    }

    func testStartCueRunsBeforeCaptureOpens() {
        var order: [String] = []
        SoundPlayer.playStartCueThenOpenCapture(
            playStart: { order.append("cue") },
            openCapture: { order.append("mic") }
        )
        XCTAssertEqual(order, ["cue", "mic"])
    }
}
