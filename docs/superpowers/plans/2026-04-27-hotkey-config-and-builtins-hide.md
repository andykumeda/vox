# Hotkey Config + Builtins Hide + Help Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the record / mode-toggle / paste hotkeys user-configurable, add a global mode-toggle hotkey that flips `forceProseMode` with icon + sound feedback, hide built-in dictionary entries from Settings, and ship an in-app Help window backed by bundled markdown.

**Architecture:** A `Hotkey` Codable value type (defined in `Sources/vox/Hotkey/Hotkey.swift`) describes any binding (Fn, or modifier+keycode, with press-hold or tap-toggle trigger). `AppSettings` exposes three new properties — `recordHotkey`, `modeToggleHotkey`, `pasteHotkey` — backed by JSON-encoded `Data` in `UserDefaults`, with `NotificationCenter` posts on change. `HotkeyMonitor` is rewritten to take both bindings via `configure(...)` and dispatch press / release / mode-toggle callbacks from a single `CGEventTap`. `TextInjector.paste` now takes a `shortcut: Hotkey` argument (defaults to `AppSettings.pasteHotkey`) and synthesizes the configured combo. `SettingsView` gains a new Hotkeys section with a `HotkeyRecorderField` widget that opens an ephemeral `CGEventTap` to capture user input, plus a filter that hides `isBuiltIn` entries from the Dictionary list. A new `HelpWindow` (SwiftUI) renders bundled `Resources/help.md` via `AttributedString(markdown:)` and is launched from a Settings button + a status-menu item.

**Tech Stack:** Swift 5.x, SPM (`swift build` / `swift test`), XCTest, SwiftUI, AppKit, `Carbon.HIToolbox` for `kVK_…`, `CoreGraphics` `CGEventTap`, Foundation `JSONEncoder`/`JSONDecoder`, `NotificationCenter`.

**Spec:** `docs/superpowers/specs/2026-04-27-hotkey-config-and-builtins-hide-design.md`

---

## File Structure

### New files

| Path | Responsibility |
|---|---|
| `Sources/vox/Hotkey/Hotkey.swift` | `Hotkey` Codable struct + `Key`, `Modifier`, `TriggerMode` enums + defaults + validation + conflict-equality helper. |
| `Sources/vox/Hotkey/HotkeyRecorder.swift` | Class-based ephemeral `CGEventTap` that captures one keystroke (or Fn-only press) and returns a `Hotkey` via completion handler. UI-driven only; no shared state. |
| `Sources/vox/App/HelpWindow.swift` | `HelpView` SwiftUI view + `HelpWindowController` `NSWindow` wrapper. Reads bundled `help.md`, renders via `AttributedString(markdown:)`. |
| `Resources/help.md` | Bundled help content shipped inside the .app. |
| `Tests/voxTests/HotkeyTests.swift` | Codable round-trip + validation + conflict-detection tests. |
| `Tests/voxTests/HotkeyMonitorTests.swift` | Pure-function tests for `HotkeyMonitor.matches(event:hotkey:)` extracted helper. |

### Modified files

| Path | Change |
|---|---|
| `Sources/vox/Hotkey/HotkeyMonitor.swift` | Rewrite. Single `CGEventTap` dispatches to record-press / record-release / mode-toggle handlers. Supports both `.pressHold` and `.tapToggle` for the record binding; mode-toggle is always tap-toggle with a 150 ms debounce. Exposes a static `matches(event:hotkey:)` helper for unit tests. |
| `Sources/vox/Util/AppSettings.swift` | Add `recordHotkey`, `modeToggleHotkey`, `pasteHotkey` properties (read/write `Hotkey` as JSON `Data` in `UserDefaults`); `NotificationCenter` posts on record/mode-toggle changes. |
| `Sources/vox/Text/TextInjector.swift` | `paste(_:keepOnClipboard:shortcut:)` accepts a `Hotkey` and synthesizes the configured combo via `CGEvent`. Default value reads `AppSettings.pasteHotkey` at call time. |
| `Sources/vox/App/MenuBarController.swift` | Wire mode-toggle handler; reconfigure `HotkeyMonitor` on `.recordHotkeyChanged` / `.modeToggleHotkeyChanged`; update icon on `forceProseMode` change; play `NSSound(named: "Tink")` on toggle; expose `showHelp()` for status menu + Settings. Add a "Help…" item to the status menu. |
| `Sources/vox/App/SettingsWindow.swift` | Add Hotkeys section with `HotkeyRecorderField` rows. Filter Dictionary list to user entries only; show "N built-in fixups active" caption. Add "Open Help" button next to "Reveal in Finder". |
| `scripts/build-app.sh` | Copy `Resources/help.md` into `dist/Vox.app/Contents/Resources/`. |

---

## Conventions

- **Working directory:** `/Users/andy/Dev/vox` (or a feature worktree spawned by the subagent-driven workflow). All paths below are repo-relative.
- **Build:** `swift build` from repo root. **App bundle:** `./scripts/build-app.sh`.
- **Test:** `swift test`. Filter: `swift test --filter <ClassName>`.
- **Commits:** No GPG signing on this branch (`git commit --no-gpg-sign`). Match existing terse imperative commit style.
- **No comments** unless explaining a non-obvious WHY.
- **`@MainActor` discipline:** Anything that mutates `@Published` SwiftUI state hops to main. The hotkey CGEventTap callback fires on the main run loop (we add the source to `CFRunLoopGetMain()`), so handler closures execute on main without explicit hops.

---

## Task 1: `Hotkey` value type + tests

**Files:**
- Create: `Sources/vox/Hotkey/Hotkey.swift`
- Create: `Tests/voxTests/HotkeyTests.swift`

- [ ] **Step 1.1: Write the failing test file**

Create `Tests/voxTests/HotkeyTests.swift`:

```swift
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
```

- [ ] **Step 1.2: Run tests to verify they fail**

Run: `swift test --filter HotkeyTests 2>&1 | tail -10`
Expected: build error — `cannot find 'Hotkey' in scope`.

- [ ] **Step 1.3: Implement `Hotkey`**

Create `Sources/vox/Hotkey/Hotkey.swift`:

```swift
import Foundation
import Carbon.HIToolbox

public struct Hotkey: Codable, Equatable, Sendable {
    public var key: Key
    public var modifiers: Set<Modifier>
    public var triggerMode: TriggerMode
    public var enabled: Bool

    public init(key: Key, modifiers: Set<Modifier>, triggerMode: TriggerMode, enabled: Bool) {
        self.key = key
        self.modifiers = modifiers
        self.triggerMode = triggerMode
        self.enabled = enabled
    }

    public var isValid: Bool {
        switch key {
        case .fn:
            return modifiers.isEmpty
        case .keycode:
            return !modifiers.isEmpty
        }
    }

    /// Conflict semantics: same (key, modifiers), regardless of trigger or enabled.
    /// Disabled bindings never conflict.
    public static func conflict(_ a: Hotkey, _ b: Hotkey) -> Bool {
        guard a.enabled, b.enabled else { return false }
        return a.key == b.key && a.modifiers == b.modifiers
    }
}

public enum Key: Codable, Equatable, Sendable {
    case fn
    case keycode(UInt16)
}

public enum Modifier: String, Codable, CaseIterable, Sendable {
    case command
    case control
    case option
    case shift
}

public enum TriggerMode: String, Codable, Sendable {
    case pressHold
    case tapToggle
}

public extension Hotkey {
    static let defaultRecord = Hotkey(
        key: .fn,
        modifiers: [],
        triggerMode: .pressHold,
        enabled: true
    )

    static let defaultModeToggle = Hotkey(
        key: .keycode(UInt16(kVK_ANSI_M)),
        modifiers: [.control, .option],
        triggerMode: .tapToggle,
        enabled: true
    )

    static let defaultPaste = Hotkey(
        key: .keycode(UInt16(kVK_ANSI_V)),
        modifiers: [.command],
        triggerMode: .tapToggle,
        enabled: true
    )
}
```

- [ ] **Step 1.4: Run tests to verify they pass**

Run: `swift test --filter HotkeyTests 2>&1 | tail -10`
Expected: 10 tests, 0 failures.

- [ ] **Step 1.5: Commit**

```bash
git add Sources/vox/Hotkey/Hotkey.swift Tests/voxTests/HotkeyTests.swift
git commit --no-gpg-sign -m "Add Hotkey value type with Codable, validation, and conflict helper"
```

---

## Task 2: `AppSettings` extension

**Files:**
- Modify: `Sources/vox/Util/AppSettings.swift`

- [ ] **Step 2.1: Read the current file**

Run: `cat Sources/vox/Util/AppSettings.swift` — note the existing `enum AppSettings` block at lines 27–52 with `keepKey`, `modelKey`, `forceProseKey` constants and properties.

- [ ] **Step 2.2: Add hotkey properties + notifications**

Append before the closing `}` of `enum AppSettings`:

```swift
    private static let recordHotkeyKey = "recordHotkey"
    private static let modeToggleHotkeyKey = "modeToggleHotkey"
    private static let pasteHotkeyKey = "pasteHotkey"

    static var recordHotkey: Hotkey {
        get { readHotkey(forKey: recordHotkeyKey) ?? .defaultRecord }
        set {
            writeHotkey(newValue, forKey: recordHotkeyKey)
            NotificationCenter.default.post(name: .recordHotkeyChanged, object: nil)
        }
    }

    static var modeToggleHotkey: Hotkey {
        get { readHotkey(forKey: modeToggleHotkeyKey) ?? .defaultModeToggle }
        set {
            writeHotkey(newValue, forKey: modeToggleHotkeyKey)
            NotificationCenter.default.post(name: .modeToggleHotkeyChanged, object: nil)
        }
    }

    static var pasteHotkey: Hotkey {
        get { readHotkey(forKey: pasteHotkeyKey) ?? .defaultPaste }
        set { writeHotkey(newValue, forKey: pasteHotkeyKey) }
    }

    private static func readHotkey(forKey key: String) -> Hotkey? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Hotkey.self, from: data)
    }

    private static func writeHotkey(_ h: Hotkey, forKey key: String) {
        if let data = try? JSONEncoder().encode(h) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

extension Notification.Name {
    static let recordHotkeyChanged = Notification.Name("vox.recordHotkeyChanged")
    static let modeToggleHotkeyChanged = Notification.Name("vox.modeToggleHotkeyChanged")
}
```

(The closing `}` of `enum AppSettings` was the existing one; the `Notification.Name` extension lives at file scope below it.)

- [ ] **Step 2.3: Verify the package compiles**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`.

- [ ] **Step 2.4: Run all tests**

Run: `swift test 2>&1 | tail -5`
Expected: 124 + 10 = 134 tests, 0 failures (Hotkey tests from Task 1 already in the suite).

- [ ] **Step 2.5: Commit**

```bash
git add Sources/vox/Util/AppSettings.swift
git commit --no-gpg-sign -m "AppSettings: add recordHotkey, modeToggleHotkey, pasteHotkey + notifications"
```

---

## Task 3: `HotkeyMonitor.matches(event:hotkey:)` extracted helper + tests

**Files:**
- Create: `Tests/voxTests/HotkeyMonitorTests.swift`
- Modify: `Sources/vox/Hotkey/HotkeyMonitor.swift`

This task adds a pure-function helper and its tests before the bigger rewrite, so we have known-good event-matching logic to lean on in Task 4.

- [ ] **Step 3.1: Write the failing test file**

Create `Tests/voxTests/HotkeyMonitorTests.swift`:

```swift
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
```

- [ ] **Step 3.2: Run tests to verify they fail**

Run: `swift test --filter HotkeyMonitorTests 2>&1 | tail -10`
Expected: build error — `static method 'matches(keycode:flags:hotkey:)' not found`.

- [ ] **Step 3.3: Add the static helper to the existing `HotkeyMonitor`**

Open `Sources/vox/Hotkey/HotkeyMonitor.swift`. Inside the `HotkeyMonitor` class (anywhere — the `start()` / `stop()` rewrite is Task 4; this step adds only the helper), add:

```swift
    /// Pure-function event matcher. `keycode == nil` means "modifier-only event"
    /// (e.g., Fn flag changes). Returns true when the event represents this hotkey.
    public static func matches(keycode: UInt16?, flags: CGEventFlags, hotkey: Hotkey) -> Bool {
        guard hotkey.enabled else { return false }
        switch hotkey.key {
        case .fn:
            // Fn-only: secondaryFn flag set, no other modifier flags, no keycode.
            let otherMods: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            return flags.contains(.maskSecondaryFn)
                && flags.intersection(otherMods).isEmpty
                && keycode == nil
        case .keycode(let target):
            guard let kc = keycode, kc == target else { return false }
            let actual: Set<Modifier> = {
                var s: Set<Modifier> = []
                if flags.contains(.maskCommand)   { s.insert(.command) }
                if flags.contains(.maskControl)   { s.insert(.control) }
                if flags.contains(.maskAlternate) { s.insert(.option) }
                if flags.contains(.maskShift)     { s.insert(.shift) }
                return s
            }()
            return actual == hotkey.modifiers
        }
    }
```

- [ ] **Step 3.4: Run tests to verify they pass**

Run: `swift test --filter HotkeyMonitorTests 2>&1 | tail -10`
Expected: 6 tests, 0 failures.

- [ ] **Step 3.5: Commit**

```bash
git add Sources/vox/Hotkey/HotkeyMonitor.swift Tests/voxTests/HotkeyMonitorTests.swift
git commit --no-gpg-sign -m "HotkeyMonitor: add static matches(keycode:flags:hotkey:) + 6 tests"
```

---

## Task 4: Rewrite `HotkeyMonitor` to support configurable bindings

**Files:**
- Modify: `Sources/vox/Hotkey/HotkeyMonitor.swift`

The rewrite swaps the hardcoded Fn check for `Hotkey`-driven dispatch. Single `CGEventTap` listens for `[.flagsChanged, .keyDown, .keyUp]` and routes to record / mode-toggle handlers using the `matches(...)` helper from Task 3.

- [ ] **Step 4.1: Replace the file body**

Open `Sources/vox/Hotkey/HotkeyMonitor.swift` and replace the entire file with:

```swift
import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Monitors the configured record and mode-toggle hotkeys via a single CGEventTap.
/// Emits press / release / mode-toggle callbacks on the main queue.
public final class HotkeyMonitor {
    public var onRecordPress: (() -> Void)?
    public var onRecordRelease: (() -> Void)?
    public var onModeToggle: (() -> Void)?

    private var record: Hotkey
    private var modeToggle: Hotkey

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var isRecordActive = false            // pressHold-held or tapToggle-on
    private var pressedKeycode: UInt16?           // captured at keyDown, used at keyUp
    private var lastModeToggleAt: CFAbsoluteTime = 0
    private static let modeToggleDebounceSeconds: CFAbsoluteTime = 0.150

    public init(
        record: Hotkey = AppSettings.recordHotkey,
        modeToggle: Hotkey = AppSettings.modeToggleHotkey
    ) {
        self.record = record
        self.modeToggle = modeToggle
    }

    /// Update bindings without restarting the tap.
    public func configure(record: Hotkey, modeToggle: Hotkey) {
        self.record = record
        self.modeToggle = modeToggle
        // If recording was active under an old binding, finalize it.
        if isRecordActive {
            isRecordActive = false
            pressedKeycode = nil
            DispatchQueue.main.async { [weak self] in self?.onRecordRelease?() }
        }
    }

    public func start() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            return false
        }
        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    public func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Dispatch

    private func handle(type: CGEventType, event: CGEvent) {
        let flags = event.flags
        let keycode: UInt16? = {
            if type == .keyDown || type == .keyUp {
                return UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            }
            return nil
        }()

        // Mode toggle (always tap-toggle, debounced).
        if type == .keyDown,
           Self.matches(keycode: keycode, flags: flags, hotkey: modeToggle) {
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastModeToggleAt >= Self.modeToggleDebounceSeconds {
                lastModeToggleAt = now
                DispatchQueue.main.async { [weak self] in self?.onModeToggle?() }
            }
            return
        }

        // Record hotkey.
        let recordEvent: Bool
        switch record.key {
        case .fn:
            recordEvent = (type == .flagsChanged)
        case .keycode:
            recordEvent = (type == .keyDown || type == .keyUp)
        }
        guard recordEvent else { return }

        let isMatch = Self.matches(keycode: keycode, flags: flags, hotkey: record)

        switch record.triggerMode {
        case .pressHold:
            handlePressHold(type: type, isMatch: isMatch, keycode: keycode)
        case .tapToggle:
            handleTapToggle(type: type, isMatch: isMatch)
        }
    }

    private func handlePressHold(type: CGEventType, isMatch: Bool, keycode: UInt16?) {
        switch type {
        case .flagsChanged:
            // Used for Fn-only bindings. isMatch reflects whether Fn is held now.
            if isMatch && !isRecordActive {
                isRecordActive = true
                DispatchQueue.main.async { [weak self] in self?.onRecordPress?() }
            } else if !isMatch && isRecordActive && record.key == .fn {
                isRecordActive = false
                pressedKeycode = nil
                DispatchQueue.main.async { [weak self] in self?.onRecordRelease?() }
            }
        case .keyDown:
            if isMatch && !isRecordActive {
                isRecordActive = true
                pressedKeycode = keycode
                DispatchQueue.main.async { [weak self] in self?.onRecordPress?() }
            }
        case .keyUp:
            // Modifier flags may already be cleared by the time keyUp fires, so
            // match strictly on the keycode captured at press time.
            if let kc = keycode, kc == pressedKeycode, isRecordActive {
                isRecordActive = false
                pressedKeycode = nil
                DispatchQueue.main.async { [weak self] in self?.onRecordRelease?() }
            }
        default:
            break
        }
    }

    private func handleTapToggle(type: CGEventType, isMatch: Bool) {
        guard type == .keyDown, isMatch else { return }
        isRecordActive.toggle()
        if isRecordActive {
            DispatchQueue.main.async { [weak self] in self?.onRecordPress?() }
        } else {
            DispatchQueue.main.async { [weak self] in self?.onRecordRelease?() }
        }
    }

    // MARK: - Static helper (kept from Task 3)

    public static func matches(keycode: UInt16?, flags: CGEventFlags, hotkey: Hotkey) -> Bool {
        guard hotkey.enabled else { return false }
        switch hotkey.key {
        case .fn:
            let otherMods: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            return flags.contains(.maskSecondaryFn)
                && flags.intersection(otherMods).isEmpty
                && keycode == nil
        case .keycode(let target):
            guard let kc = keycode, kc == target else { return false }
            let actual: Set<Modifier> = {
                var s: Set<Modifier> = []
                if flags.contains(.maskCommand)   { s.insert(.command) }
                if flags.contains(.maskControl)   { s.insert(.control) }
                if flags.contains(.maskAlternate) { s.insert(.option) }
                if flags.contains(.maskShift)     { s.insert(.shift) }
                return s
            }()
            return actual == hotkey.modifiers
        }
    }
}
```

- [ ] **Step 4.2: Verify the package compiles**

Run: `swift build 2>&1 | tail -10`
Expected: `Build complete!`. The pre-existing `MenuBarController.swift` Sendable warnings are unrelated.

- [ ] **Step 4.3: Run all tests**

Run: `swift test 2>&1 | tail -5`
Expected: all tests pass (Hotkey + HotkeyMonitor static-helper tests + previously existing 124).

- [ ] **Step 4.4: Commit**

```bash
git add Sources/vox/Hotkey/HotkeyMonitor.swift
git commit --no-gpg-sign -m "HotkeyMonitor: configurable bindings, pressHold + tapToggle modes, mode-toggle dispatch"
```

---

## Task 5: `TextInjector` configurable paste keystroke

**Files:**
- Modify: `Sources/vox/Text/TextInjector.swift`

- [ ] **Step 5.1: Read the current file**

Run: `cat Sources/vox/Text/TextInjector.swift` — locate the `paste(_:keepOnClipboard:)` method (currently synthesizes Cmd+V via `CGEvent` with hardcoded keycode for `V` and `.maskCommand`).

- [ ] **Step 5.2: Add a `shortcut:` parameter**

Replace the existing `paste(_:keepOnClipboard:)` signature and body with:

```swift
    /// Writes `text` to the pasteboard and synthesizes the configured paste shortcut.
    public func paste(
        _ text: String,
        keepOnClipboard: Bool,
        shortcut: Hotkey = AppSettings.pasteHotkey
    ) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        guard shortcut.enabled, case .keycode(let kc) = shortcut.key else {
            // Fn or invalid binding — fall back to ⌘V (defensive).
            sendKeyCombo(keycode: UInt16(kVK_ANSI_V), modifiers: [.command])
            if !keepOnClipboard { schedulePasteboardClear() }
            return
        }

        var mods: CGEventFlags = []
        if shortcut.modifiers.contains(.command) { mods.insert(.maskCommand) }
        if shortcut.modifiers.contains(.control) { mods.insert(.maskControl) }
        if shortcut.modifiers.contains(.option)  { mods.insert(.maskAlternate) }
        if shortcut.modifiers.contains(.shift)   { mods.insert(.maskShift) }

        sendKeyCombo(keycode: kc, modifiers: mods)
        if !keepOnClipboard { schedulePasteboardClear() }
    }

    private func sendKeyCombo(keycode: UInt16, modifiers: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keycode, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keycode, keyDown: false)
        down?.flags = modifiers
        up?.flags = modifiers
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
```

The `schedulePasteboardClear()` helper is the existing private method that clears the pasteboard after a delay; do NOT modify it. Also remove the old hardcoded Cmd+V code path that this replaces.

> If a `private func schedulePasteboardClear()` does NOT exist, search the file for the post-paste clear logic and either extract it into a method with that exact name (so the snippet above compiles) or inline the clear logic into both branches above. Either is acceptable; pick whichever produces a smaller diff.

- [ ] **Step 5.3: Verify the package compiles**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`.

- [ ] **Step 5.4: Run all tests**

Run: `swift test 2>&1 | tail -5`
Expected: no regressions.

- [ ] **Step 5.5: Commit**

```bash
git add Sources/vox/Text/TextInjector.swift
git commit --no-gpg-sign -m "TextInjector: paste() takes configurable Hotkey shortcut, defaults to AppSettings.pasteHotkey"
```

---

## Task 6: `MenuBarController` wiring — mode toggle, icon, sound, reconfigure

**Files:**
- Modify: `Sources/vox/App/MenuBarController.swift`

- [ ] **Step 6.1: Update record-hotkey wiring to use new `HotkeyMonitor` API**

Open `Sources/vox/App/MenuBarController.swift`. Find where `hotkey.onPress` and `hotkey.onRelease` are assigned (currently lines 71–80 area). Rename to the new API and add the mode-toggle handler:

```swift
        hotkey.onRecordPress = { [weak self] in
            self?.startRecording()
        }
        hotkey.onRecordRelease = { [weak self] in
            self?.stopRecording()
        }
        hotkey.onModeToggle = { [weak self] in
            self?.handleModeToggle()
        }
```

(Where `startRecording` / `stopRecording` are the existing private methods called by the prior `onPress` / `onRelease`. Rename if needed to match the existing closure bodies — keep parity with current behavior.)

- [ ] **Step 6.2: Add `handleModeToggle()` method**

Add a new private method on `MenuBarController`:

```swift
    private func handleModeToggle() {
        AppSettings.forceProseMode.toggle()
        refreshIcon()
        NSSound(named: NSSound.Name("Tink"))?.play()
    }
```

- [ ] **Step 6.3: Add `refreshIcon()` and call it on launch + when force changes**

Add a new private method:

```swift
    private func refreshIcon() {
        let symbolName: String
        switch state {
        case .idle:
            symbolName = AppSettings.forceProseMode ? "lock.bubble.fill" : "text.bubble.fill"
        case .recording:
            symbolName = "mic.fill"
        case .transcribing:
            symbolName = "waveform"
        }
        let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Vox")
        img?.isTemplate = true
        statusItem.button?.image = img
    }
```

Find the existing icon-update sites (likely scattered alongside `state = .recording` / `state = .transcribing` / `state = .idle`). Replace each with a call to `refreshIcon()` after the state assignment. If the state is currently set via a `didSet` observer, just call `refreshIcon()` from the `didSet`.

If `lock.bubble.fill` is unavailable on the target macOS version, fall back to overlaying a small lock glyph on `text.bubble.fill`. For v1 simplicity, if the symbol returns `nil`, accept the fallback to no image rather than crashing — `statusItem.button?.image = nil` is acceptable. Confirm by running the app after build (Task 11 manual smoke).

- [ ] **Step 6.4: Subscribe to hotkey-change notifications**

Add an init-time observer registration. Inside `applicationDidFinishLaunching` (or wherever the existing `hotkey.start()` happens), add:

```swift
        NotificationCenter.default.addObserver(
            forName: .recordHotkeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reconfigureHotkey()
        }
        NotificationCenter.default.addObserver(
            forName: .modeToggleHotkeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reconfigureHotkey()
        }
```

Add `reconfigureHotkey()`:

```swift
    private func reconfigureHotkey() {
        hotkey.stop()
        hotkey.configure(
            record: AppSettings.recordHotkey,
            modeToggle: AppSettings.modeToggleHotkey
        )
        _ = hotkey.start()
    }
```

- [ ] **Step 6.5: Add help-window controller field + `showHelp()` method**

Add a private field to `MenuBarController`:

```swift
    private var helpWindowController: HelpWindowController?
```

Add a method (the `HelpWindowController` type is defined in Task 9; this code compiles only after Task 9 lands. Apply this step regardless and rely on Task 9's commit to make the file compile end-to-end. Until then, comment out the body or guard with `#if false`):

```swift
    public func showHelp() {
        if helpWindowController == nil {
            helpWindowController = HelpWindowController()
        }
        helpWindowController?.show()
    }
```

> **Engineer note:** the Task 6 commit will not compile until Task 9 lands. To keep the working tree green, defer Step 6.5 to a follow-up commit AFTER Task 9 is done. Or, equivalently, reorder: do Task 9 before Task 6's Step 6.5 commit.

- [ ] **Step 6.6: Add a "Help…" menu item to the status menu**

Find the existing status menu construction (likely a method that builds an `NSMenu` with "Settings…", "Quit", etc.). Insert a "Help…" item above "Settings…":

```swift
        menu.addItem(
            NSMenuItem(
                title: "Help…",
                action: #selector(showHelpAction(_:)),
                keyEquivalent: ""
            )
        )
        menu.addItem(.separator())
```

Add an `@objc` action method that calls `showHelp()`:

```swift
    @objc private func showHelpAction(_ sender: Any?) {
        showHelp()
    }
```

- [ ] **Step 6.7: Verify compile (deferring 6.5/6.6 if Task 9 not done)**

If you applied Steps 6.5 / 6.6 before Task 9, expect `cannot find 'HelpWindowController' in scope`. Comment out those bodies temporarily, run `swift build 2>&1 | tail -5`, expect `Build complete!`, then proceed.

If you sequenced the work properly (Task 9 first), `swift build` should succeed unconditionally.

- [ ] **Step 6.8: Run all tests**

Run: `swift test 2>&1 | tail -5`
Expected: no regressions.

- [ ] **Step 6.9: Commit**

```bash
git add Sources/vox/App/MenuBarController.swift
git commit --no-gpg-sign -m "MenuBarController: mode-toggle handler, icon refresh, hotkey reconfigure, Help… menu"
```

---

## Task 7: SettingsWindow — hide builtins from Dictionary list

**Files:**
- Modify: `Sources/vox/App/SettingsWindow.swift`

- [ ] **Step 7.1: Filter `dict.entries` to user-only and update caption**

Open `Sources/vox/App/SettingsWindow.swift`. In the body of `SettingsView`, locate the Dictionary section's ScrollView+LazyVStack. Replace the `ForEach(Array(dict.entries.enumerated()), id: \.element.id) { idx, entry in ... }` block with this user-only variant (keeping the bordered ScrollView wrapper):

```swift
                let userEntries = dict.entries.filter { !$0.isBuiltIn }
                let builtinCount = dict.entries.count - userEntries.count
                let disabledCount = userEntries.filter { !$0.enabled }.count

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if userEntries.isEmpty {
                            VStack(spacing: 6) {
                                Text("No custom entries yet.")
                                    .foregroundStyle(.secondary)
                                Text("Click Add to create one.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(builtinCount) built-in fixups active")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity)
                        } else {
                            ForEach(Array(userEntries.enumerated()), id: \.element.id) { idx, entry in
                                DictionaryRow(
                                    entry: entry,
                                    onToggle: { dict.setEnabled(id: entry.id, enabled: !entry.enabled) },
                                    onEdit: { editingEntry = entry; isAddingEntry = false },
                                    onDelete: { dict.delete(id: entry.id) }
                                )
                                .padding(.horizontal, 8)
                                if idx < userEntries.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .frame(minHeight: 240, maxHeight: 400)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )

                Text("\(userEntries.count) custom entries · \(disabledCount) disabled · \(builtinCount) built-in fixups active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
```

(Replaces both the existing `ScrollView { LazyVStack { ForEach… } }` and the `Text("\(dict.entries.count) entries · …")` caption below it.)

- [ ] **Step 7.2: Verify the package compiles**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`.

- [ ] **Step 7.3: Run all tests**

Run: `swift test 2>&1 | tail -5`
Expected: no regressions.

- [ ] **Step 7.4: Commit**

```bash
git add Sources/vox/App/SettingsWindow.swift
git commit --no-gpg-sign -m "Settings: hide built-in dictionary rows; show count caption"
```

---

## Task 8: `HotkeyRecorder` + `HotkeyRecorderField` SwiftUI widget

**Files:**
- Create: `Sources/vox/Hotkey/HotkeyRecorder.swift`
- Modify: `Sources/vox/App/SettingsWindow.swift`

- [ ] **Step 8.1: Create the recorder class**

Create `Sources/vox/Hotkey/HotkeyRecorder.swift`:

```swift
import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Ephemeral CGEventTap that captures one Hotkey, then auto-stops.
public final class HotkeyRecorder {
    public typealias Completion = (Hotkey?) -> Void  // nil if cancelled

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var completion: Completion?
    private var existingTriggerMode: TriggerMode
    private var timeoutTimer: Timer?
    private static let timeoutSeconds: TimeInterval = 5

    public init(existingTriggerMode: TriggerMode) {
        self.existingTriggerMode = existingTriggerMode
    }

    public func start(completion: @escaping Completion) -> Bool {
        self.completion = completion
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let r = Unmanaged<HotkeyRecorder>.fromOpaque(refcon).takeUnretainedValue()
                r.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            completion(nil)
            return false
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: Self.timeoutSeconds, repeats: false) { [weak self] _ in
            self?.cancel()
        }
        return true
    }

    public func cancel() {
        finish(with: nil)
    }

    private func handle(type: CGEventType, event: CGEvent) {
        let flags = event.flags
        // Esc cancels.
        if type == .keyDown,
           UInt16(event.getIntegerValueField(.keyboardEventKeycode)) == UInt16(kVK_Escape) {
            DispatchQueue.main.async { [weak self] in self?.cancel() }
            return
        }
        switch type {
        case .flagsChanged:
            // Fn-only: maskSecondaryFn set, no other modifiers.
            let otherMods: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            if flags.contains(.maskSecondaryFn) && flags.intersection(otherMods).isEmpty {
                let h = Hotkey(key: .fn, modifiers: [], triggerMode: existingTriggerMode, enabled: true)
                DispatchQueue.main.async { [weak self] in self?.finish(with: h) }
            }
        case .keyDown:
            let kc = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            var mods: Set<Modifier> = []
            if flags.contains(.maskCommand)   { mods.insert(.command) }
            if flags.contains(.maskControl)   { mods.insert(.control) }
            if flags.contains(.maskAlternate) { mods.insert(.option) }
            if flags.contains(.maskShift)     { mods.insert(.shift) }
            guard !mods.isEmpty else { return }  // require at least one modifier
            let h = Hotkey(key: .keycode(kc), modifiers: mods, triggerMode: existingTriggerMode, enabled: true)
            DispatchQueue.main.async { [weak self] in self?.finish(with: h) }
        default:
            break
        }
    }

    private func finish(with hotkey: Hotkey?) {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        eventTap = nil
        runLoopSource = nil
        let cb = completion
        completion = nil
        cb?(hotkey)
    }
}
```

- [ ] **Step 8.2: Add SwiftUI `HotkeyRecorderField` and a Hotkeys section to `SettingsView`**

Open `Sources/vox/App/SettingsWindow.swift`. At the bottom (after the existing `DictionaryEditSheet`), append:

```swift
struct HotkeyRecorderField: View {
    @Binding var hotkey: Hotkey
    let label: String
    let allowTriggerModePicker: Bool
    @State private var isRecording = false
    @State private var recorder: HotkeyRecorder?
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption)
            HStack(spacing: 8) {
                Button {
                    startRecording()
                } label: {
                    Text(isRecording ? "Press your combo…" : displayString(hotkey))
                        .frame(minWidth: 200, alignment: .leading)
                }
                .buttonStyle(.bordered)

                if allowTriggerModePicker {
                    Picker("", selection: $hotkey.triggerMode) {
                        Text("Press-and-hold").tag(TriggerMode.pressHold)
                        Text("Tap-to-toggle").tag(TriggerMode.tapToggle)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }

                Button(hotkey.enabled ? "Disable" : "Enable") {
                    hotkey.enabled.toggle()
                }
            }
            if let h = hint {
                Text(h).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func startRecording() {
        isRecording = true
        hint = nil
        let r = HotkeyRecorder(existingTriggerMode: hotkey.triggerMode)
        recorder = r
        _ = r.start { [hotkey] result in
            isRecording = false
            recorder = nil
            if let captured = result, captured.isValid {
                self.hotkey = Hotkey(
                    key: captured.key,
                    modifiers: captured.modifiers,
                    triggerMode: hotkey.triggerMode,
                    enabled: true
                )
            } else if result != nil {
                hint = "Combo needs at least one modifier."
            } // nil = cancelled / timeout, leave existing binding
        }
    }
}

private func displayString(_ h: Hotkey) -> String {
    if !h.enabled { return "(disabled)" }
    switch h.key {
    case .fn:
        return "Fn"
    case .keycode(let kc):
        let prefix = displayModifiers(h.modifiers)
        return prefix + keyName(forKeycode: kc)
    }
}

private func displayModifiers(_ mods: Set<Modifier>) -> String {
    var s = ""
    if mods.contains(.control) { s += "⌃" }
    if mods.contains(.option)  { s += "⌥" }
    if mods.contains(.shift)   { s += "⇧" }
    if mods.contains(.command) { s += "⌘" }
    return s
}

private func keyName(forKeycode kc: UInt16) -> String {
    let map: [UInt16: String] = [
        UInt16(kVK_ANSI_A): "A", UInt16(kVK_ANSI_B): "B", UInt16(kVK_ANSI_C): "C",
        UInt16(kVK_ANSI_D): "D", UInt16(kVK_ANSI_E): "E", UInt16(kVK_ANSI_F): "F",
        UInt16(kVK_ANSI_G): "G", UInt16(kVK_ANSI_H): "H", UInt16(kVK_ANSI_I): "I",
        UInt16(kVK_ANSI_J): "J", UInt16(kVK_ANSI_K): "K", UInt16(kVK_ANSI_L): "L",
        UInt16(kVK_ANSI_M): "M", UInt16(kVK_ANSI_N): "N", UInt16(kVK_ANSI_O): "O",
        UInt16(kVK_ANSI_P): "P", UInt16(kVK_ANSI_Q): "Q", UInt16(kVK_ANSI_R): "R",
        UInt16(kVK_ANSI_S): "S", UInt16(kVK_ANSI_T): "T", UInt16(kVK_ANSI_U): "U",
        UInt16(kVK_ANSI_V): "V", UInt16(kVK_ANSI_W): "W", UInt16(kVK_ANSI_X): "X",
        UInt16(kVK_ANSI_Y): "Y", UInt16(kVK_ANSI_Z): "Z",
        UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1", UInt16(kVK_ANSI_2): "2",
        UInt16(kVK_ANSI_3): "3", UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5",
        UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7", UInt16(kVK_ANSI_8): "8",
        UInt16(kVK_ANSI_9): "9",
        UInt16(kVK_Space): "Space", UInt16(kVK_Return): "Return",
        UInt16(kVK_Tab): "Tab", UInt16(kVK_Escape): "Esc",
    ]
    return map[kc] ?? "key(\(kc))"
}
```

(`Carbon.HIToolbox` must be importable from `SettingsWindow.swift`. Add `import Carbon.HIToolbox` at the top of the file if not already present.)

Then, inside `SettingsView.body`, after the Model/Usage sections and before the Dictionary section, add:

```swift
            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Hotkeys").font(.headline)

                HotkeyRecorderField(
                    hotkey: Binding(
                        get: { AppSettings.recordHotkey },
                        set: { AppSettings.recordHotkey = $0 }
                    ),
                    label: "Record dictation",
                    allowTriggerModePicker: true
                )

                HotkeyRecorderField(
                    hotkey: Binding(
                        get: { AppSettings.modeToggleHotkey },
                        set: { AppSettings.modeToggleHotkey = $0 }
                    ),
                    label: "Toggle mode (auto / force prose)",
                    allowTriggerModePicker: false
                )

                HotkeyRecorderField(
                    hotkey: Binding(
                        get: { AppSettings.pasteHotkey },
                        set: { AppSettings.pasteHotkey = $0 }
                    ),
                    label: "Paste keystroke (sent to focused app)",
                    allowTriggerModePicker: false
                )

                Button("Reset all to defaults") {
                    AppSettings.recordHotkey = .defaultRecord
                    AppSettings.modeToggleHotkey = .defaultModeToggle
                    AppSettings.pasteHotkey = .defaultPaste
                }
                .controlSize(.small)
            }
```

- [ ] **Step 8.3: Verify the package compiles**

Run: `swift build 2>&1 | tail -10`
Expected: `Build complete!`.

If you get `cannot find 'Carbon' in scope`: add `import Carbon.HIToolbox` to the top of `SettingsWindow.swift`.

- [ ] **Step 8.4: Run all tests**

Run: `swift test 2>&1 | tail -5`
Expected: no regressions.

- [ ] **Step 8.5: Commit**

```bash
git add Sources/vox/Hotkey/HotkeyRecorder.swift Sources/vox/App/SettingsWindow.swift
git commit --no-gpg-sign -m "Add HotkeyRecorder + Settings Hotkeys section with recorder field"
```

---

## Task 9: `HelpWindow` + bundled `Resources/help.md`

**Files:**
- Create: `Sources/vox/App/HelpWindow.swift`
- Create: `Resources/help.md`

- [ ] **Step 9.1: Write `Resources/help.md`**

Create `Resources/help.md` with this content (verbatim):

```markdown
# Vox — Quick Help

## Recording
Hold **Fn** (default) and speak. Release to transcribe.
Switch trigger to **tap-to-toggle** in Settings → Hotkeys if you prefer one-tap-start, one-tap-stop.

## Modes
- **Prose** — natural sentences, capitalized, with terminal punctuation. Default for most apps.
- **Command** — verbatim shell commands, no capitalization, no trailing punctuation. Auto-selected when the focused app is a terminal (Terminal, iTerm, Wave, etc.).
Press your **Mode toggle** hotkey (default `⌃⌥M`) to force prose regardless of focus. The menu-bar icon shows a lock when prose is forced.

## Dictionary
Settings → Dictionary lets you define custom substitutions:
- Spoken `vox` → replacement `Vox` (proper-noun fix in prose).
- Spoken `next field` → replacement `next tab` to insert "next" + Tab key.
- Mode scope: command, prose, or both.
- "Match only at start" anchors to the first word of an utterance.
12 built-in fixups are active behind the scenes (e.g., `ls -shell` → `ls -l`). To silence one, click **Reveal in Finder**, open `dictionary.json`, set `"enabled": false`, save. The change reloads automatically.

## Key-press substitutions
A replacement that ends with one of these words fires that key after pasting:
- `tab` — Tab (needs at least one preceding word)
- `return`, `enter`, `newline` — Return
- `escape`, `esc` — Esc
- `control X` — Ctrl+X (any letter)

## Hotkeys
Settings → Hotkeys lets you rebind:
- **Record dictation** (default Fn, press-and-hold).
- **Toggle mode** (default `⌃⌥M`, tap).
- **Paste keystroke** (default `⌘V`, sent to the focused app to inject text).

## Files
- Dictionary: `~/Library/Application Support/Vox/dictionary.json`
- Logs: `~/Library/Logs/vox.log`

## Troubleshooting
- **Paste fails silently** — make sure Vox launched via `open dist/Vox.app`, not the binary directly. TCC attributes Accessibility permissions to the launching process.
- **Fn key doesn't fire** — System Settings → Keyboard → "Press 🌐 key to" must be **Do Nothing**.
- **Wrong transcription on short phrases** — add a Dictionary entry to fix the specific misfire (e.g., spoken `-shell` → `-l`).
```

- [ ] **Step 9.2: Create `HelpWindow.swift`**

Create `Sources/vox/App/HelpWindow.swift`:

```swift
import AppKit
import SwiftUI

struct HelpView: View {
    @State private var attributed: AttributedString?

    var body: some View {
        ScrollView {
            if let s = attributed {
                Text(s)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            } else {
                Text("Help unavailable.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .frame(width: 640, height: 720)
        .onAppear { loadHelp() }
    }

    private func loadHelp() {
        guard let url = Bundle.main.url(forResource: "help", withExtension: "md"),
              let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .utf8) else { return }
        attributed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )
    }
}

public final class HelpWindowController {
    private var window: NSWindow?

    public init() {}

    @MainActor
    public func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: HelpView())
        let w = NSWindow(contentViewController: hosting)
        w.title = "Vox Help"
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.minSize = NSSize(width: 480, height: 400)
        w.center()
        w.isReleasedWhenClosed = false
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 9.3: Update `Package.swift` to include `Resources/help.md`**

Open `Package.swift`. Locate the `target` definition for `vox` (the executable). Confirm it has a `resources:` clause for any existing files (it likely already lists `Resources/AppIcon.icns` or similar). Add the help file to the resources list:

```swift
resources: [
    .process("Resources/help.md"),
    // ... existing resources ...
]
```

If `Package.swift` does NOT currently use `resources:` on the vox target (because the .app bundle is built by `scripts/build-app.sh` directly, not by SPM), skip this step — the build script will copy the file in Task 10. The runtime `Bundle.main.url(forResource:)` reads from the .app's Resources directory, populated by the script.

- [ ] **Step 9.4: Verify the package compiles**

Run: `swift build 2>&1 | tail -10`
Expected: `Build complete!`. If `Bundle.main.url(forResource: "help", withExtension: "md")` returns nil under `swift test` / debug build, that's expected — the help.md only loads when running from the .app bundle.

- [ ] **Step 9.5: Run all tests**

Run: `swift test 2>&1 | tail -5`
Expected: no regressions.

- [ ] **Step 9.6: Commit**

```bash
git add Sources/vox/App/HelpWindow.swift Resources/help.md Package.swift
git commit --no-gpg-sign -m "Add HelpWindow + bundled help.md"
```

(If `Package.swift` was untouched, drop it from the `git add` line.)

---

## Task 10: `scripts/build-app.sh` — copy `help.md` into the bundle

**Files:**
- Modify: `scripts/build-app.sh`

- [ ] **Step 10.1: Read the existing script**

Run: `cat scripts/build-app.sh` — locate the section that copies `Resources/AppIcon.icns` (or other resources) into `dist/Vox.app/Contents/Resources/`.

- [ ] **Step 10.2: Add a copy line for help.md**

Find the `cp Resources/AppIcon.icns "$APP_PATH/Contents/Resources/"` line (or equivalent) and add directly below it:

```bash
cp Resources/help.md "$APP_PATH/Contents/Resources/"
```

If no such block exists, locate where the bundle's `Contents/Resources/` directory is created (likely a `mkdir -p ...Resources` line) and add both `mkdir -p` (if needed) and the `cp` line there.

- [ ] **Step 10.3: Run the script and verify the file lands in the bundle**

Run: `./scripts/build-app.sh && ls dist/Vox.app/Contents/Resources/help.md`
Expected: file exists at the listed path.

- [ ] **Step 10.4: Commit**

```bash
git add scripts/build-app.sh
git commit --no-gpg-sign -m "build-app.sh: copy Resources/help.md into the .app bundle"
```

---

## Task 11: Add Settings "Open Help" button + manual integration smoke

**Files:**
- Modify: `Sources/vox/App/SettingsWindow.swift`

- [ ] **Step 11.1: Add the "Open Help" button**

In `SettingsWindow.swift`, find the Dictionary section's button row (the existing `Add` + `Reveal in Finder` buttons). Append a new button after `Reveal in Finder`:

```swift
                    Button {
                        HelpWindowController().show()
                    } label: {
                        Label("Open Help", systemImage: "questionmark.circle")
                    }
```

(Constructing a fresh `HelpWindowController()` each click is acceptable — `show()` ignores the held window if it has been disposed; the `MenuBarController.showHelp()` path is the singleton entry. For tighter coupling, inject `MenuBarController.shared` if such a pattern exists in the codebase. If not, keep the simple `HelpWindowController()` instantiation for v1.)

- [ ] **Step 11.2: Verify the package compiles**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`.

- [ ] **Step 11.3: Run all tests**

Run: `swift test 2>&1 | tail -5`
Expected: all tests pass.

- [ ] **Step 11.4: Commit**

```bash
git add Sources/vox/App/SettingsWindow.swift
git commit --no-gpg-sign -m "Settings: add Open Help button"
```

- [ ] **Step 11.5: Manual integration smoke**

Run: `./scripts/build-app.sh && open dist/Vox.app`

Verify in the running app:
1. **Help window:** click `Open Help` in Settings AND the menu-bar `Help…` item — both open the same-style help window with rendered Markdown headings, lists, and inline code spans. No "Help unavailable" message.
2. **Hide builtins:** Settings → Dictionary → no built-in rows shown; caption reads `0 custom entries · 0 disabled · 12 built-in fixups active`.
3. **Add a user entry:** click Add, fill spoken=`vox`, replacement=`Vox`, mode=`prose`, save. Caption updates to `1 custom entries · 0 disabled · 12 built-in fixups active`. Dictate "running vox today" in a prose context, verify "Running Vox today." pastes.
4. **Mode toggle:** press `⌃⌥M`. Hear a Tink sound. Status-bar icon changes to a lock variant. Press `⌃⌥M` again, sound replays, icon reverts.
5. **Rebind record hotkey:** Settings → Hotkeys → click the Record field → press `⌃⌥R`. Field now reads `⌃⌥R`. Hold `⌃⌥R` (or tap if trigger mode is set to tap-toggle), dictate, release. Verify recording fires with new binding.
6. **Reset to defaults:** click `Reset all to defaults`. Record returns to `Fn`, mode toggle to `⌃⌥M`, paste to `⌘V`.
7. **Paste shortcut rebind:** rebind paste to `⌃⇧V`. Dictate; verify paste lands (some apps may not respond to `⌃⇧V` — try in TextEdit or Notes which handle it).
8. **Restart preserves bindings:** quit, reopen via `open dist/Vox.app`, confirm Settings still shows the bindings you set.

If any step fails, report the failure with the relevant log lines from `~/Library/Logs/vox.log` and the steps that reproduce it.

---

## Self-review checklist

- [x] Spec coverage: every section of `2026-04-27-hotkey-config-and-builtins-hide-design.md` maps to at least one task. Schema → Task 1; AppSettings → Task 2; Monitor helper → Task 3; Monitor rewrite → Task 4; TextInjector → Task 5; MenuBarController + icon + sound + reconfigure + status menu → Task 6; hide builtins → Task 7; Recorder + Hotkeys section → Task 8; HelpWindow + help.md → Task 9; build-app.sh copy → Task 10; Open Help button + smoke → Task 11.
- [x] No placeholders. The Task 4 sub-section flagged the original `UInt16Equals` stub as needing simplification and provides the corrected `pressedKeycode` approach inline.
- [x] Type names consistent: `Hotkey`, `Key`, `Modifier`, `TriggerMode`, `HotkeyMonitor.matches(keycode:flags:hotkey:)`, `HotkeyRecorder`, `HotkeyRecorderField`, `HelpWindowController` referenced uniformly across tasks.
- [x] Each TDD-able task (1, 3) writes the failing test before implementation. UI-heavy tasks (6, 7, 8, 9, 11) rely on manual smoke as documented.
- [x] Commits land at task boundaries; no oversized changes.

---

## Out of scope (explicit, v1)

- Three-state mode cycle (auto / force-command / force-prose).
- Per-app paste-hotkey overrides.
- Manual replay of the last transcription.
- Effective-mode icon based on focused app.
- Markdown rendering beyond `AttributedString(markdown:)`.
- A UI surface for editing built-in dictionary entries (JSON edit retained as advanced workflow).
- Localization of help content.
