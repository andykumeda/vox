# Hotkey Config, Mode Toggle, Hide Built-ins, and Help — Design

**Status:** Approved (pre-implementation)
**Date:** 2026-04-27
**Owner:** Andy

## Problem

Four related gaps in the current Vox UX:

1. **Built-in dictionary entries clutter Settings.** The 12 seeded misfire fixups (e.g., `-shell` → `-l`) appear as rows users can't truly delete, only disable. Most users never need to see them.
2. **No way to override mode mid-session.** When `ContextDetector` mis-classifies the focused app or the user wants prose in a terminal context, they must either dictate in the wrong mode or open Settings to flip `forceProseMode`. A global hotkey would be much faster.
3. **Hotkeys are hardcoded.** Record uses Fn (no choice), paste uses ⌘V (no choice). Users with non-standard keyboards or apps that use different paste bindings can't adapt.
4. **No in-app help.** Users discover features by trial, asking, or reading the README. The app needs a single "what does this do" surface that ships with the build.

## Goals

- Hide built-in dictionary entries from the Settings UI; keep them functional.
- Add a global mode-toggle hotkey that flips `forceProseMode` and shows a visible state cue.
- Make the record, mode-toggle, and paste hotkeys all user-configurable in Settings.
- Bundle a one-page help document inside the .app and surface it via a Help window.

## Non-Goals (v1)

- Three-state mode cycle (auto / force-command / force-prose).
- Per-app paste-hotkey overrides.
- Manual replay of the last transcription.
- Menu-bar icon that mirrors effective mode based on focused app (only the force-prose state is reflected).
- Markdown features beyond what `AttributedString(markdown:)` supports.
- A UI surface for editing built-in dictionary entries (JSON edit retained as advanced workflow).
- Localization of help content.

## Architecture

```
┌────────────────────────────────────┐
│ AppSettings (UserDefaults)         │
│   .recordHotkey:    Hotkey         │   Codable structs, JSON-encoded
│   .pasteHotkey:     Hotkey         │   into UserDefaults Data per key
│   .modeToggleHotkey: Hotkey        │
│   .forceProseMode:  Bool (existing)│
└──────┬─────────────────────────────┘
       │ on launch + on Settings save
       ▼
┌────────────────────────────────────┐                ┌─────────────────────────┐
│ HotkeyMonitor (rewritten)          │  press/release │ MenuBarController       │
│   .configure(record:modeToggle:)   │ ─────────────▶ │   onPress / onRelease   │
│   single CGEventTap, dispatches    │                │   onModeToggle          │
│   to record vs modeToggle handlers │                └─────┬───────────────────┘
└────────────────────────────────────┘                      │
                                                            │ updates
                                                            ▼
                                            ┌──────────────────────────────────┐
                                            │ Effective mode + status item icon│
                                            │   sound on toggle                │
                                            └──────────────────────────────────┘

┌────────────────────────────────────┐  used at injection
│ TextInjector                       │  time
│   .paste(text, shortcut: Hotkey)   │  reads AppSettings.pasteHotkey
└────────────────────────────────────┘

┌────────────────────────────────────┐  reads bundled
│ HelpWindow (SwiftUI)               │  Resources/help.md
│   renders Markdown via             │  via Bundle.main.url(forResource:)
│   AttributedString(markdown:)      │
└────────────────────────────────────┘

┌────────────────────────────────────┐  filter !isBuiltIn
│ SettingsView Dictionary section    │  in ForEach;
│   shows user entries only          │  caption "12 built-in fixups active"
└────────────────────────────────────┘
```

### New files
- `Sources/vox/Hotkey/Hotkey.swift` — Codable struct + `Modifier` enum + `Key` wrapper + defaults.
- `Sources/vox/Hotkey/HotkeyRecorder.swift` — ephemeral `CGEventTap` for "press your combo" capture in Settings.
- `Sources/vox/App/HelpWindow.swift` — SwiftUI window rendering bundled `help.md`.
- `Resources/help.md` — bundled help content.
- `Tests/voxTests/HotkeyTests.swift` — Codable round-trip + conflict detection.

### Modified files
- `Sources/vox/Hotkey/HotkeyMonitor.swift` — rewrite to support arbitrary key+modifier bindings, both press-hold and tap-toggle modes, plus mode-toggle dispatch.
- `Sources/vox/Util/AppSettings.swift` — add three hotkey properties.
- `Sources/vox/Text/TextInjector.swift` — `paste()` accepts a `Hotkey` instead of hardcoded ⌘V.
- `Sources/vox/App/MenuBarController.swift` — wire mode-toggle handler, icon swap, sound on toggle.
- `Sources/vox/App/SettingsWindow.swift` — Hotkeys section + Help button + filter built-ins from Dictionary list.
- `scripts/build-app.sh` — copy `Resources/help.md` into `.app/Contents/Resources/`.

## Hotkey schema

```swift
public struct Hotkey: Codable, Equatable, Sendable {
    public var key: Key
    public var modifiers: Set<Modifier>      // empty for Fn-only
    public var triggerMode: TriggerMode      // .pressHold or .tapToggle
    public var enabled: Bool                 // can disable a binding entirely
}

public enum Key: Codable, Equatable, Sendable {
    case fn                                  // matches CGEventFlags.maskSecondaryFn
    case keycode(UInt16)                     // any kVK_… raw value
}

public enum Modifier: String, Codable, CaseIterable, Sendable {
    case command, control, option, shift
    // No `.fn` — Fn lives in Key (it's the lone "key" with no other key).
}

public enum TriggerMode: String, Codable, Sendable {
    case pressHold      // record while held (Fn-style); fires onRelease too
    case tapToggle      // tap to start, tap to stop
}
```

### Validation rules
A `Hotkey` is valid when either:
- `key == .fn` AND `modifiers` is empty, OR
- `key == .keycode(c)` AND `modifiers` is non-empty.

`triggerMode == .pressHold` is meaningful only for the record hotkey. The mode-toggle and paste hotkeys are always `.tapToggle`; the UI hides the trigger-mode picker for those rows.

### Conflict detection
Two `Hotkey` values "conflict" when their `(key, modifiers)` pair is equal — `triggerMode` and `enabled` are ignored. Disabled bindings are excluded from conflict checks. Settings UI shows a non-blocking ⚠ caption under conflicting fields; saving is allowed.

### Display formatting
- `⌃⌥M` for `.keycode(kVK_M) + {control, option}`.
- `Fn` for `.fn`.
- Standard SF Symbols glyphs: ⌘ ⌥ ⌃ ⇧.

## Hotkey recorder UI

A new `Hotkeys` section sits between Model and Usage in `SettingsView`:

```
─────────────────────────────────────────────────
Hotkeys

  Record dictation
    [ Fn                         ] [ Recording mode: Press-and-hold ▾ ]
    Click to change · ⓘ Press the combo you want.

  Toggle mode (auto / force prose)
    [ ⌃⌥M                        ] [ Disable ]
    ⓘ Cycles forceProseMode on / off.

  Paste keystroke (sent to focused app)
    [ ⌘V                         ]
    ⓘ Used to inject the transcription. Most apps expect ⌘V.

  [ Reset all to defaults ]
─────────────────────────────────────────────────
```

### Recorder widget (`HotkeyRecorderField`)
- Idle: shows current binding (e.g., `⌃⌥M`) inside a button-like field.
- Click: enters "recording" state; label changes to "Press your combo…"; opens an ephemeral `CGEventTap` for `flagsChanged + keyDown`.
- On capture: tap returns `Hotkey { key, modifiers, triggerMode: existing }`, recorder closes, field updates.
- Esc cancels; "Disable" button sets `enabled = false`.
- Trigger-mode picker is its own `Picker` next to the field for the record hotkey only (mode-toggle and paste are always tap-style).

### Recorder logic
- Single `CGEventTap`, `.cgSessionEventTap`, mask `[.flagsChanged, .keyDown]`.
- Fn-only binding: detect `flags.maskSecondaryFn` set with no other modifier flags AND no key event — capture as `.fn`.
- Combo binding: on `keyDown`, capture `event.flags & relevantMask` → modifiers, `event.keyCode` → `.keycode`. Require ≥1 modifier (bare key without modifier is rejected with brief "needs a modifier" caption).
- Tap auto-cancels after 5 s of inactivity.

### Save semantics
- "Save" button at the bottom of Settings (already exists). Hotkeys live-write to `AppSettings` on field commit.
- `MenuBarController` re-configures `HotkeyMonitor` on `AppSettings` change via `NotificationCenter` (`.recordHotkeyChanged`, `.modeToggleHotkeyChanged`).
- Paste hotkey takes effect immediately on next paste call; no monitor reconfig needed.

### Reset-to-defaults
Button overwrites all three hotkeys with shipped defaults:
- Record: `Hotkey(.fn, [], .pressHold, true)`
- Mode toggle: `Hotkey(.keycode(kVK_M), [.control, .option], .tapToggle, true)`
- Paste: `Hotkey(.keycode(kVK_V), [.command], .tapToggle, true)`

## Mode-toggle behavior + indicators

### Toggle action
On mode-toggle hotkey fire:
1. `AppSettings.forceProseMode.toggle()`
2. Refresh menu-bar icon.
3. Play `SoundPlayer.play(.modeToggle)` — new short ~80 ms blip.

### State model
- `forceProseMode == false` (auto): `ContextDetector` decides command vs prose from focused app's bundle ID (current behavior).
- `forceProseMode == true` (forced): all dictations use prose, regardless of focused app.

No "force command" state. Bundle-id detection covers terminals already; users wanting force-command can simply switch focus.

### Menu-bar icon

| State | Icon |
|---|---|
| Idle, force-off (auto) | `text.bubble.fill` (current) |
| Idle, force-on (prose forced) | `lock.bubble.fill` (or `text.bubble.fill` overlaid with a small lock — chosen at implementation time based on SF Symbol availability) |
| Recording | `mic.fill` (existing) |
| Transcribing | `waveform` (existing) |

Recording and transcribing icons unchanged regardless of force state.

### Tap-toggle debounce
The mode-toggle hotkey uses `.tapToggle`. `HotkeyMonitor` debounces ≥150 ms between consecutive fires to avoid double-fire on key bounce.

## Hide built-ins from Dictionary list

UI-only filter in `SettingsWindow.swift`:

```swift
let userEntries = dict.entries.filter { !$0.isBuiltIn }
let builtinCount = dict.entries.count - userEntries.count
let disabledCount = userEntries.filter { !$0.enabled }.count

// ScrollView { LazyVStack { ForEach(userEntries) { ... } } }

Text("\(userEntries.count) custom entries · \(disabledCount) disabled · \(builtinCount) built-in fixups active")
    .font(.caption)
    .foregroundStyle(.secondary)
```

When `userEntries.count == 0`, show a centered empty state in the bordered scroll area: "No custom entries yet. Click Add to create one. (\(builtinCount) built-in fixups active)".

The built-in disable path is preserved via JSON edit — documented in help.

No code change to `DictionaryStore`. Storage, seed-merge, and watcher behavior stay identical.

## Help system

### Bundled file
`Resources/help.md`. Built into `.app/Contents/Resources/help.md` via `scripts/build-app.sh`. The script's existing copy block extends to include this file (one new line).

### Help window
`Sources/vox/App/HelpWindow.swift` — SwiftUI window. Loaded once by `MenuBarController`; shown via menu-bar item "Help…" or "Open Help" button in Settings.

```swift
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
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
    }
}
```

### Window lifecycle
- Singleton `NSWindow` held by `MenuBarController`. `showHelp()` brings it forward; second invocation re-uses the same window.
- Style: titled, closable, miniaturizable. Minimum size 480×400.

### Entry points
1. Settings: button next to "Reveal in Finder" labelled "Open Help".
2. Menu-bar status menu: a "Help…" item above "Settings…" / "Quit".

### Help content (initial draft, ships in `Resources/help.md`)
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
| Word | Key |
|---|---|
| `tab` | Tab (needs ≥1 preceding word) |
| `return`, `enter`, `newline` | Return |
| `escape`, `esc` | Esc |
| `control X` | Ctrl+X |

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

## Persistence + first-launch defaults

### `AppSettings` extension
```swift
enum AppSettings {
    // existing keys ...
    private static let recordHotkeyKey = "recordHotkey"
    private static let modeToggleHotkeyKey = "modeToggleHotkey"
    private static let pasteHotkeyKey = "pasteHotkey"

    static var recordHotkey: Hotkey {
        get { read(.recordHotkeyKey) ?? .defaultRecord }
        set { write(newValue, .recordHotkeyKey); post(.recordHotkeyChanged) }
    }

    static var modeToggleHotkey: Hotkey {
        get { read(.modeToggleHotkeyKey) ?? .defaultModeToggle }
        set { write(newValue, .modeToggleHotkeyKey); post(.modeToggleHotkeyChanged) }
    }

    static var pasteHotkey: Hotkey {
        get { read(.pasteHotkeyKey) ?? .defaultPaste }
        set { write(newValue, .pasteHotkeyKey) }
    }

    private static func read(_ key: String) -> Hotkey? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Hotkey.self, from: data)
    }
    private static func write(_ h: Hotkey, _ key: String) {
        if let data = try? JSONEncoder().encode(h) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    private static func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}

extension Notification.Name {
    static let recordHotkeyChanged = Notification.Name("vox.recordHotkeyChanged")
    static let modeToggleHotkeyChanged = Notification.Name("vox.modeToggleHotkeyChanged")
}
```

### Hotkey defaults (in `Hotkey.swift`)
```swift
public extension Hotkey {
    static let defaultRecord = Hotkey(
        key: .fn, modifiers: [], triggerMode: .pressHold, enabled: true
    )
    static let defaultModeToggle = Hotkey(
        key: .keycode(UInt16(kVK_ANSI_M)),
        modifiers: [.control, .option],
        triggerMode: .tapToggle, enabled: true
    )
    static let defaultPaste = Hotkey(
        key: .keycode(UInt16(kVK_ANSI_V)),
        modifiers: [.command],
        triggerMode: .tapToggle, enabled: true
    )
}
```

### First launch & upgrade
No migration needed. `read(...) ?? .defaultX` lazily returns the default. The existing `forceProseMode` setting is unchanged; the mode-toggle hotkey lives alongside it.

### `HotkeyMonitor` reconfiguration
- `MenuBarController.init` subscribes to `.recordHotkeyChanged` and `.modeToggleHotkeyChanged`.
- On notification: `hotkey.stop(); hotkey.configure(record:, modeToggle:, onRecordPress:, onRecordRelease:, onModeToggle:); _ = hotkey.start()`.
- Mid-recording rebind: any active recording is finalized as if the user released early.

### `TextInjector.paste` signature
```swift
public func paste(_ text: String, keepOnClipboard: Bool, shortcut: Hotkey = AppSettings.pasteHotkey)
```
Default reads at call time, so live changes apply on next paste. Tests inject explicit shortcut.

## Testing

### `HotkeyTests` (new)
- `testCodableRoundTripFn`
- `testCodableRoundTripCombo`
- `testEqualityIgnoresEnabled` — full struct equality is exact; `enabled` is part of the struct.
- `testEqualityForConflictDetection` — separate helper compares only `(key, modifiers)`.
- `testValidatesFnHasNoModifiers` — `.fn + {.command}` is invalid.
- `testValidatesComboRequiresModifier` — `.keycode + []` is invalid.
- `testDefaultsAreValid` — each `.defaultX` passes validation.
- `testConflictDetectionFindsClash` — record == paste hotkey returns conflict.
- `testConflictDetectionIgnoresDisabled` — disabled bindings don't conflict.

### `HotkeyMonitor` tests (limited)
- `testConfigureSwapsBindingsWithoutRestart`
- `testTapToggleDebouncesRapidFires`

### Help bundling test
- `testHelpFileBundled` — assert `Bundle.main.url(forResource: "help", withExtension: "md")` is non-nil. Skipped under `swift test`; runs only as integration after the .app build.

### Manual smoke (extends prior Task 10)
- Settings Hotkeys: rebind record to `⌃⌥R`, verify recording works.
- Settings Hotkeys: rebind paste to `⌃⇧V`, dictate something, verify paste fires the new combo.
- Mode toggle: press `⌃⌥M`, verify icon changes to lock variant; press again, icon reverts.
- Menu bar Help… opens the help window; reveal-in-finder still works.
- Settings Dictionary section: 12 built-ins are not visible as rows; caption reads "0 custom entries · 0 disabled · 12 built-in fixups active".

## Risks acknowledged

- `AttributedString(markdown:)` may render the help table awkwardly. Mitigation: keep table simple (≤4 columns); fall back to bulleted list if rendering fails.
- A user who binds ⌘V as record can no longer paste. The conflict caption surfaces this; reset-to-defaults restores.
- Fn-key change requires user to re-grant Accessibility permissions if the app's signing identity changes (orthogonal to this feature; mentioned in help).
