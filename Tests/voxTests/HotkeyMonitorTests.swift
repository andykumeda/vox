import XCTest
import CoreGraphics
import Carbon.HIToolbox
@testable import vox

final class HotkeyMonitorTests: XCTestCase {

    private func cgFlags(_ mods: Set<Modifier>, fn: Bool = false) -> CGEventFlags {
        var flags: CGEventFlags = []
        if mods.contains(.command) { flags.insert(.maskCommand) }
        if mods.contains(.control) { flags.insert(.maskControl) }
        if mods.contains(.option)  { flags.insert(.maskAlternate) }
        if mods.contains(.shift)   { flags.insert(.maskShift) }
        if fn { flags.insert(.maskSecondaryFn) }
        return flags
    }

    func testMatchesFnOnly() {
        let h = Hotkey(key: .fn, modifiers: [], triggerMode: .pressHold, enabled: true)
        let flags = cgFlags([], fn: true)
        XCTAssertTrue(HotkeyMonitor.matches(keycode: nil, flags: flags, hotkey: h))
    }

    func testFnHotkeyDoesNotMatchOtherModifiers() {
        let h = Hotkey(key: .fn, modifiers: [], triggerMode: .pressHold, enabled: true)
        let flags = cgFlags([.command], fn: false)
        XCTAssertFalse(HotkeyMonitor.matches(keycode: nil, flags: flags, hotkey: h))
    }

    func testMatchesComboKeycodeAndModifiers() {
        let h = Hotkey(
            key: .keycode(UInt16(kVK_ANSI_M)),
            modifiers: [.control, .option],
            triggerMode: .tapToggle,
            enabled: true
        )
        let flags = cgFlags([.control, .option])
        XCTAssertTrue(HotkeyMonitor.matches(
            keycode: UInt16(kVK_ANSI_M),
            flags: flags,
            hotkey: h
        ))
    }

    func testComboMissesOnDifferentKeycode() {
        let h = Hotkey(
            key: .keycode(UInt16(kVK_ANSI_M)),
            modifiers: [.control, .option],
            triggerMode: .tapToggle,
            enabled: true
        )
        let flags = cgFlags([.control, .option])
        XCTAssertFalse(HotkeyMonitor.matches(
            keycode: UInt16(kVK_ANSI_N),
            flags: flags,
            hotkey: h
        ))
    }

    func testComboMissesOnExtraModifier() {
        let h = Hotkey(
            key: .keycode(UInt16(kVK_ANSI_M)),
            modifiers: [.control, .option],
            triggerMode: .tapToggle,
            enabled: true
        )
        let flags = cgFlags([.control, .option, .shift])
        XCTAssertFalse(HotkeyMonitor.matches(
            keycode: UInt16(kVK_ANSI_M),
            flags: flags,
            hotkey: h
        ))
    }

    func testDisabledHotkeyNeverMatches() {
        let h = Hotkey(key: .fn, modifiers: [], triggerMode: .pressHold, enabled: false)
        let flags = cgFlags([], fn: true)
        XCTAssertFalse(HotkeyMonitor.matches(keycode: nil, flags: flags, hotkey: h))
    }
}
