# User Dictionary — Design

**Status:** Approved (pre-implementation)
**Date:** 2026-04-27
**Owner:** Andy

## Problem

Whisper systematically misfires on short shell utterances (`ls -l` → `ls -shall` / `hello, -shell`) and on prose proper-nouns / project-specific vocabulary (`vox` → `vox` instead of `Vox`). The current `PostProcessor.fixCommonMisfires` static map only addresses a hardcoded subset of command-mode misfires; users cannot add their own corrections without editing source. A user-editable dictionary, in the spirit of Wispr Flow's substitution list, lets users own their personal vocabulary across both modes.

## Goals

- User-editable list of `spoken → replacement` pairs.
- Works in both command mode (shell tokens, flag fixups) and prose mode (proper nouns, jargon).
- Ship with defaults that replicate today's `fixCommonMisfires` behavior.
- Defaults can be edited or disabled per entry; new defaults added in app upgrades reach existing users without overwriting their edits.
- Dictionary file is human-editable on disk; in-app UI provides a friendlier path.
- External edits and in-app edits stay in sync via a file watcher.

## Non-Goals (v1)

- Regex match type. Token-based literal matching is the only match style.
- Per-app scope (different dictionaries for different target apps).
- Sync across machines (manual file copy is acceptable).
- Snippets / multi-line replacements (mechanically supported by string replacement; no UI affordance for newline entry).

## Architecture

```
┌─────────────────┐    on launch + on file change
│ DictionaryStore │  ◀───────────────────────────── ~/Library/Application Support/Vox/dictionary.json
│  (singleton)    │           DispatchSource file watcher
└────────┬────────┘
         │  current entries (in-memory)
         ▼
┌─────────────────┐
│  PostProcessor  │  reads entries via injected provider closure
│   .process()    │  applies token-based literal substitutions as last step
└─────────────────┘

      ▲                                          ▲
      │ writes on Save                           │ user edits via
      │                                          │ "Reveal in Finder" + editor
┌─────────────────┐                              │
│  Settings UI    │ ─────────────────────────────┘ both paths converge on
│  Dictionary tab │     same JSON file; watcher reloads in-memory
└─────────────────┘
```

### New files
- `Sources/vox/Util/DictionaryEntry.swift` — `Codable` struct.
- `Sources/vox/Util/DictionaryStore.swift` — singleton, load/save/seed/watch.

### Modified files
- `Sources/vox/Text/PostProcessor.swift` — gains `dictionaryProvider` closure; `applyDictionary` step replaces `fixCommonMisfires`; `misfireReplacements` array deleted (its content migrates into `DictionaryStore.bundledDefaults`).
- `Sources/vox/App/SettingsWindow.swift` — adds Dictionary section.

## Schema

```swift
struct DictionaryEntry: Codable, Identifiable, Equatable {
    var id: String                   // "builtin-<slug>" or "user-<UUID>"
    var spoken: String               // literal, whitespace-tokenized
    var replacement: String          // literal; empty = deletion
    var mode: Scope                  // .command | .prose | .both
    var startsWith: Bool             // anchor at token index 0
    var caseInsensitive: Bool        // default true
    var enabled: Bool                // default true
    var isBuiltIn: Bool              // marks seeded defaults
}

enum Scope: String, Codable, CaseIterable { case command, prose, both }
```

### Match algorithm

1. Tokenize input by maximal runs of non-whitespace.
2. Tokenize `spoken` the same way.
3. A match is a window of consecutive input tokens equal to all `spoken` tokens (case-insensitive if flag set).
4. If `startsWith == true`, match must start at input token index 0.
5. Replace matched window with `replacement` tokens. Empty `replacement` removes the window. If the match has both a preceding and a following separator, drop the preceding one to collapse adjacent whitespace; if it has only one (start- or end-of-string match), drop that one.

This sidesteps regex word-boundary footguns: `spoken="-shell"` matches the token `-shell` but NOT inside `--shell` (a single token). Multi-word spoken matches consecutive tokens.

### Apply order within a mode

- Filter by `enabled && (mode == scope || mode == .both)`.
- Sort by descending token-count of `spoken` (longest match wins). Ties broken by file order.
- One pass per entry; each pass replaces all non-overlapping matches.

## File format

**Path:** `~/Library/Application Support/Vox/dictionary.json` (Vox dir created on first launch if absent).

**Format:** single JSON object, schema-versioned.

```json
{
  "schemaVersion": 1,
  "entries": [
    {
      "id": "builtin-shell-l",
      "spoken": "-shell",
      "replacement": "-l",
      "mode": "command",
      "startsWith": false,
      "caseInsensitive": true,
      "enabled": true,
      "isBuiltIn": true
    },
    {
      "id": "builtin-hello-ls",
      "spoken": "hello,",
      "replacement": "ls",
      "mode": "command",
      "startsWith": true,
      "caseInsensitive": true,
      "enabled": true,
      "isBuiltIn": true
    }
  ]
}
```

- Pretty-printed (`.prettyPrinted`, `.sortedKeys`) for diff-friendly manual edits.
- Atomic write: write to `dictionary.json.tmp`, then `rename()` to `dictionary.json`. Avoids partial-file reads if the watcher fires mid-save.
- IDs: built-ins use stable slugs (`builtin-<slug>`); user entries use `user-<UUID>` generated at creation.

## Default seeding & upgrade behavior

`DictionaryStore.bundledDefaults: [DictionaryEntry]` lives in code as the source-of-truth list of built-ins. Each has a stable id.

Seed-merge runs every launch, before serving entries:

1. Load `dictionary.json` from disk (empty list if absent).
2. Compute set of built-in ids already on disk: `disk.filter(\.isBuiltIn).map(\.id)`.
3. For each `bundledDefaults` entry whose id is NOT in that set, append it to the disk list.
4. If anything was appended, write back to disk.
5. Result becomes the in-memory `entries`.

**Outcomes:**
- **First launch** — file absent → empty load → all built-ins appended → file written with full default set.
- **Upgrade adds new built-in** — new id appended; user's edits and disabled-flags on existing built-ins preserved.
- **User deletes a built-in** — id reappears on next launch (intentional). UI exposes "Disable" instead of "Delete" for built-in rows; deleting a built-in via external JSON edit is treated as accidental.
- **User edits a built-in's `spoken`/`replacement`** — preserved. Merge only adds missing ids; never overwrites existing rows.

**Tradeoff acknowledged:** if a built-in's default replacement is later improved (e.g., I change `-shell → -l` to a better default), users who haven't edited it still get the *old* version because the id already exists. Acceptable: built-in ids represent intent-stable rules; significant functional changes ship as new ids.

## Pipeline integration

### Command mode (after change)
```
lowercase → strip-trailing-punct → expandSpokenPunctuation
  → splitCommandFromFlag → applyDictionary(.command)
  → extractTrailingSuffixKeys
```

`fixCommonMisfires` and its `misfireReplacements` array are deleted; the seven entries migrate to `bundledDefaults` (with stable ids: `builtin-shell-l`, `builtin-shall-l`, `builtin-sell-l`, `builtin-cell-l`, `builtin-hey-a`, `builtin-hay-a`, `builtin-hello-ls`, `builtin-hi-ls`, `builtin-hey-ls`).

### Prose mode (after change)
```
capitalizeSentenceStarts → ensureTrailingTerminator
  → applyDictionary(.prose)
```

Dictionary runs after capitalize so mid-sentence proper-noun fixes (`vox` → `Vox`) work.

### URL shielding

Dictionary runs **while URLs are still shielded**. Shielded segments are wrapped in Private-Use-Area markers (`U+E000`…`U+E001`) and survive tokenization as opaque non-whitespace tokens; user entries cannot accidentally target them with normal ASCII spoken text.

### Suffix-key extraction order

`extractTrailingSuffixKeys` runs **after** dictionary so user can't accidentally make `enter` not fire as Return key.

### Injection

```swift
public init(
    mode: TranscriptionMode,
    dictionaryProvider: @escaping () -> [DictionaryEntry] = { DictionaryStore.shared.entries }
)
```

Tests pass an explicit closure for deterministic entries.

## Settings UI

New section in `SettingsView` after Usage panel, separated by `Divider`.

```
Dictionary                                    [+ Add]
                                              [📂 Reveal in Finder]

┌──────────────────────────────────────────────────────┐
│ Spoken    Replacement   Mode      Anchor  Enabled    │
├──────────────────────────────────────────────────────┤
│ -shell    -l            command   ─       ☑   ⚙ 🚫 │  ← built-in
│ hello,    ls            command   start   ☑   ⚙ 🚫 │
│ vox       Vox           prose     ─       ☑   ⚙ 🗑 │  ← user
└──────────────────────────────────────────────────────┘

11 entries · 3 disabled
```

- SwiftUI `List` (or `Table`) bound to `@StateObject` wrapping `DictionaryStore`.
- Columns: Spoken, Replacement, Mode (Picker), Anchor (`startsWith` shown as `start`/`─`), Enabled toggle, Edit (sheet), Delete/Disable.
- **Add** opens edit sheet pre-filled with empty entry, `mode=.command`, `enabled=true`, `isBuiltIn=false`, generated id.
- **Edit sheet:** `TextField` for spoken/replacement, `Picker` for mode, `Toggle` for `startsWith` and `caseInsensitive`. Save / Cancel. Save validates `spoken` non-empty.
- **Reveal in Finder:** `NSWorkspace.shared.activateFileViewerSelecting([dictionaryURL])`.
- **Built-in vs user delete UX:** built-ins show 🚫 disable icon (toggles `enabled`); user entries show 🗑 trash with confirm dialog.
- **Live update:** when watcher fires, `DictionaryStore` reloads and emits `objectWillChange`; UI rebinds. If sheet is open during external reload, sheet retains its working copy and shows banner: "Dictionary changed on disk."
- **Validation feedback:** empty spoken shows red border + "Spoken is required."

## File watcher

`DispatchSource.makeFileSystemObjectSource` on `dictionary.json`:

- Mask: `[.write, .extend, .rename, .delete]`.
- Debounce 250 ms before reload (atomic-rename produces clustered events).
- After every reload, re-bind watcher (file descriptor invalidated by atomic write).
- If the file is deleted, recreate it from `bundledDefaults`.

## Error handling

| Failure | Behavior |
|---|---|
| File missing on launch | Create file, seed defaults, log info. |
| JSON malformed | Keep last-good in-memory entries (or `bundledDefaults` if first launch). Non-blocking alert: "Dictionary file invalid (JSON parse error at line N). Edits not loaded." Watcher remains live. |
| Schema version unknown / future | Same as malformed. |
| Duplicate ids in file | Keep first occurrence, drop later, log warning. No alert. |
| Disk write fails on Save | Alert: "Could not save dictionary: <reason>." Keep in-memory state; user retries. |
| File watcher init fails | Log warning; fall back to reload on `NSApplication.didBecomeActiveNotification`. |

## Concurrency

All `DictionaryStore` mutation hops to the main actor. `PostProcessor` reads entries via the provider closure on whatever thread post-processing runs; the provider returns a `[DictionaryEntry]` value-type snapshot, copied at the call site, so no shared mutable state crosses threads.

## Testing

### `DictionaryStoreTests` (new)
- First-launch seeds all built-ins.
- Upgrade scenario: existing file missing one built-in id → that id appended on next load; existing edits preserved.
- Disabled built-in stays disabled across re-load.
- User entry survives reload.
- Malformed JSON → fallback path; alert flag set.
- Duplicate id → first wins.
- Atomic write produces valid file (round-trip equality).

### `PostProcessorTests` (extend existing)
- All current `testCommandFixes*` misfire tests still pass with default-seeded entries.
- Scope filter: prose entry does not fire in command mode and vice versa.
- `mode=.both` fires in both.
- Token boundary: `-shell` rule does not match inside `--shell`.
- `startsWith` rule only fires at index 0.
- Multi-token spoken: `"my email"` → `"andy@kumeda.com"`.
- Empty replacement deletes tokens.
- Disabled entry is a no-op.
- Sort order: longer match wins over shorter.
- Tests inject explicit `dictionaryProvider` closure — never read disk.

### Integration (manual)
- Open Settings, add entry, dictate command, observe substitution.
- Edit JSON externally, watcher reloads, dictate again, see new behavior without app restart.
- Disable a built-in, verify dictation no longer applies it.
- Delete the JSON file via Finder, verify it regenerates with bundled defaults on next dictation.
