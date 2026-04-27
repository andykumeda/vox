import XCTest
import Carbon.HIToolbox
@testable import vox

final class HotkeyTests: XCTestCase {

    func testCodableRoundTripFn() throws {
        let h = Hotkey(key: .fn, modifiers: [], triggerMode: .pressHold, enabled: true)
        let data = try JSONEncoder().encode(h)
        let decoded = try JSONDecoder().decode(Hotkey.self, from: data)
        XCTAssertEqual(decoded, h)
    }

    func testCodableRoundTripCombo() throws {
        let h = Hotkey(
            key: .keycode(UInt16(kVK_ANSI_M)),
            modifiers: [.control, .option],
            triggerMode: .tapToggle,
            enabled: true
        )
        let data = try JSONEncoder().encode(h)
        let decoded = try JSONDecoder().decode(Hotkey.self, from: data)
        XCTAssertEqual(decoded, h)
    }

    func testEqualityIsExact() {
        let a = Hotkey(key: .fn, modifiers: [], triggerMode: .pressHold, enabled: true)
        let b = Hotkey(key: .fn, modifiers: [], triggerMode: .pressHold, enabled: false)
        XCTAssertNotEqual(a, b)
    }

    func testValidatesFnHasNoModifiers() {
        let bad = Hotkey(key: .fn, modifiers: [.command], triggerMode: .pressHold, enabled: true)
        XCTAssertFalse(bad.isValid)
    }

    func testValidatesComboRequiresModifier() {
        let bad = Hotkey(
            key: .keycode(UInt16(kVK_ANSI_M)),
            modifiers: [],
            triggerMode: .tapToggle,
            enabled: true
        )
        XCTAssertFalse(bad.isValid)
    }

    func testFnAloneIsValid() {
        let ok = Hotkey(key: .fn, modifiers: [], triggerMode: .pressHold, enabled: true)
        XCTAssertTrue(ok.isValid)
    }

    func testComboWithModifierIsValid() {
        let ok = Hotkey(
            key: .keycode(UInt16(kVK_ANSI_M)),
            modifiers: [.control, .option],
            triggerMode: .tapToggle,
            enabled: true
        )
        XCTAssertTrue(ok.isValid)
    }

    func testDefaultsAreValid() {
        XCTAssertTrue(Hotkey.defaultRecord.isValid)
        XCTAssertTrue(Hotkey.defaultModeToggle.isValid)
        XCTAssertTrue(Hotkey.defaultPaste.isValid)
    }

    func testConflictDetectionFindsClash() {
        let a = Hotkey(
            key: .keycode(UInt16(kVK_ANSI_V)),
            modifiers: [.command], triggerMode: .tapToggle, enabled: true
        )
        let b = Hotkey(
            key: .keycode(UInt16(kVK_ANSI_V)),
            modifiers: [.command], triggerMode: .pressHold, enabled: true
        )
        XCTAssertTrue(Hotkey.conflict(a, b))
    }

    func testConflictDetectionDifferentKeys() {
        let a = Hotkey(key: .fn, modifiers: [], triggerMode: .pressHold, enabled: true)
        let b = Hotkey(
            key: .keycode(UInt16(kVK_ANSI_V)),
            modifiers: [.command], triggerMode: .tapToggle, enabled: true
        )
        XCTAssertFalse(Hotkey.conflict(a, b))
    }

    func testConflictDetectionIgnoresDisabled() {
        let a = Hotkey(
            key: .keycode(UInt16(kVK_ANSI_V)),
            modifiers: [.command], triggerMode: .tapToggle, enabled: true
        )
        let b = Hotkey(
            key: .keycode(UInt16(kVK_ANSI_V)),
            modifiers: [.command], triggerMode: .tapToggle, enabled: false
        )
        XCTAssertFalse(Hotkey.conflict(a, b))
    }
}
