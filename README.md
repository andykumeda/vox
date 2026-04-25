# Vox

Push-to-talk voice dictation for macOS (Apple Silicon). Hold **Fn** to speak, release to transcribe with OpenAI's `gpt-4o-mini-transcribe` (default) or `gpt-4o-transcribe` / `whisper-1`. Output is pasted at the cursor in whichever app has focus.

Context-aware: when the frontmost app is a terminal (`Terminal.app`, `iTerm2`, `Warp`, `Ghostty`, `Alacritty`, `kitty`, `WezTerm`, `Hyper`, `Wave`, `Tabby`), Vox switches to **command mode** — no auto-capitalize, no trailing period, aggressive number-to-digit conversion, spoken-punctuation expansion (`dash`, `dot`, `pipe`), NATO phonetic letters after dashes, and trailing-keyword key-event synthesis (`tab`, `return`, `escape`, `control X`). Otherwise, **prose mode** — capitalizes sentence starts, ensures a space after `.`, `!`, `?`, detects questions, and synthesizes a Space keystroke for inter-sentence separation.

## Requirements

- macOS 13+ on Apple Silicon
- Xcode 16+ command-line tools (`xcode-select --install`) — ships with Swift 6
- An [OpenAI API key](https://platform.openai.com/api-keys)

## Quick start (recommended)

```sh
./scripts/setup.sh
```

One-shot bootstrap: preflight checks (Xcode tools, Swift, OpenSSL), creates the `vox-dev` signing identity if missing, builds, launches, and prints the permission-grant checklist. Idempotent — safe to re-run.

## Manual build

```sh
./scripts/create-dev-cert.sh   # ONE TIME — persistent self-signed identity
./scripts/build-app.sh
open build/Vox.app
```

`create-dev-cert.sh` creates a self-signed `vox-dev` identity in the login keychain. Signing every build with the same identity keeps macOS **TCC permissions sticky across rebuilds**. Skip it and the build falls back to ad-hoc signing — every rebuild revokes Accessibility / Input Monitoring / Microphone, forcing re-permit.

`build-app.sh` probes for the `vox-dev` identity in two phases: (a) `find-identity -v -p codesigning` against the default search list (cert in System keychain, key in login — typical), then (b) the login keychain alone without `-v` (MDM-managed Macs where the cert can't reach System trust). Designated requirement is pinned to the cert SHA so Keychain ACLs don't re-prompt every rebuild.

## Launch

Always launch via `open`, not by running the binary directly:

```sh
open build/Vox.app
```

Running `./build/Vox.app/Contents/MacOS/vox` from a shell makes the process a child of the terminal, and TCC attributes Accessibility grants to the terminal instead of Vox — paste silently fails.

### First-run permissions

macOS will prompt three times. Grant each:

1. **Microphone** — required to record audio.
2. **Input Monitoring** — required for the `CGEventTap` that watches the Fn key.
3. **Accessibility** — required to synthesize Cmd+V into the focused app.

If Fn doesn't trigger: **System Settings → Keyboard → "Press 🌐 key to"** → set to *Do Nothing* (or rebind), otherwise macOS intercepts Fn for the emoji/dictation picker.

## Settings

Click the menu bar bubble icon → **Settings…**

- **OpenAI API key** — stored in the macOS Keychain (`com.andykumeda.vox` / `openai-api-key`). Click **Always Allow** on the keychain prompt the first time.
- **Model** — pick `gpt-4o-mini-transcribe` (~$0.003/min, default), `gpt-4o-transcribe` (~$0.006/min, best quality), or `whisper-1` (~$0.006/min, no prompt-following).
- **Usage (lifetime)** — calls, audio minutes, words, USD estimate. Refresh + Reset buttons. Estimate = `audioMinutes × model.usdPerMinute`.
- **Always use prose mode** — overrides terminal context detection. Flip on when dictating prose into a terminal (commit messages, READMEs, chat).
- **Keep transcription on clipboard after paste** — when on, transcribed text remains on your clipboard so you can Cmd+V again. When off (default), prior clipboard is restored ~400 ms after paste.

## Menu bar icon

| State | Icon | Color |
|---|---|---|
| Idle | `text.bubble` outline | template (adapts) |
| Recording | `text.bubble.fill` | red |
| Transcribing | `text.bubble.fill` | orange, pulsing |
| Error | `exclamationmark.triangle` | template |

The orange macOS recording indicator dot also appears whenever Vox holds the mic — that's a system privacy feature, not a Vox icon.

## Usage

Hold **Fn**, speak, release. Bubble turns red while recording, orange-pulsing while transcribing, then pastes at the cursor.

### Prose mode

- Capitalizes the first letter of each sentence.
- Detects questions: sentences starting with `is/are/was/were/do/does/did/have/has/will/would/should/can/could/may/might/must/who/what/when/where/why/how/whose/which/shall` get `?` instead of `.` when terminator is missing.
- Ensures `.`, `!`, `?` are followed by a space.
- Pastes text without a trailing space, then synthesizes a discrete **Space keypress** for inter-sentence separation. (Some apps strip trailing whitespace from pasted text — keystrokes can't be stripped.)
- Spelled-out numbers ≥10 or compound numbers convert to digits. Bare singles `<10` stay as words ("I have three apples").
- URLs, domains, IP addresses, version strings, and common file names are shielded from sentence-splitting.

### Command mode

Triggered when frontmost app is a terminal (or override via Settings).

- Lowercases mis-capitalized first letter, strips trailing `.!?`.
- Aggressive number conversion — `head -n three` → `head -n 3`.
- Splits joined flags — `ls-l` → `ls -l`.
- Spoken punctuation:
  - `dash` / `minus` → `-`
  - `double dash` / `double minus` → `--`
  - `dot` → `.` (glues filename: `readme dot md` → `readme.md`)
  - `pipe` → `|`
- NATO phonetic letters after `-` or `--`: `dash lima` → `-l`, `minus romeo foxtrot` → `-rf`, `double dash help` → `--help`.
- Trailing-keyword key-event synthesis (stripped from text, fired as keystroke after paste):

| Spoken | Action |
|---|---|
| `tab` (with prefix text) | sends Tab |
| `return` / `enter` / `newline` | sends Return (fires alone too) |
| `escape` / `esc` | sends Escape (fires alone too) |
| `control X` / `ctrl X` (X = letter A–Z) | sends Ctrl+X (fires alone too) |

Multiple keys allowed: `brew upd tab return` → pastes `brew upd`, sends Tab (completes to `brew update`), then Return (executes).

### Silence gate

Empty or very quiet recordings are dropped before hitting the transcription API (≥0.35s + RMS ≥150). Speech models hallucinate or echo the system prompt when fed silence.

## Log file

```sh
tail -f ~/Library/Logs/vox.log
```

Lines: Fn press/release, WAV byte counts, raw API response, post-processor output (text + suffixKeys + word count + cost estimate).

## Project layout

```
Package.swift            swift-tools-version 6.0, macOS 13+, Swift 5 language mode
Resources/               Info.plist, vox.entitlements, AppIcon.icns
scripts/
  build-app.sh           Builds release binary, wraps as .app, codesigns
  create-dev-cert.sh     One-time: creates stable "vox-dev" code-signing identity
  generate-icon.sh       Renders AppIcon.icns from Swift + sips + iconutil
  generate-icon.swift    SF Symbols on gradient → 1024×1024 PNG
  make-dmg.sh            Drag-to-Applications DMG packager
Sources/vox/
  App/                   AppDelegate, MenuBarController (icon/state machine), SettingsWindow (SwiftUI)
  Audio/                 AudioRecorder — AVAudioEngine → 16 kHz mono 16-bit WAV
  Context/               ContextDetector — NSWorkspace frontmost → prose/command
  Hotkey/                HotkeyMonitor — CGEventTap on Fn (kCGEventFlagMaskSecondaryFn)
  STT/                   OpenAITranscriber, TranscriptionMode (per-mode prompt)
  Text/                  PostProcessor, NumberNormalizer, TextInjector (paste + sendKey)
  Util/                  KeychainStore, SoundPlayer, AppSettings, UsageTracker
Tests/voxTests/          79 unit tests covering text-transform pipeline + context detection
```

## Testing

```sh
swift test
```

## Distribution

### Build a DMG

```sh
./scripts/make-dmg.sh
# → dist/Vox.dmg (drag-to-Applications installer)
```

### Publish a GitHub release

```sh
gh release create v0.1.0 --title "Vox 0.1.0" \
    --notes "Initial release." dist/Vox.dmg
```

### First-launch on another Mac

The DMG is **self-signed**, not Apple-notarized. Gatekeeper will say *"Vox.app cannot be opened because Apple cannot check it for malicious software."* Bypass once:

1. Right-click **Vox.app** in `/Applications` → **Open** → **Open Anyway**.

   *or equivalently from Terminal:*

   ```sh
   xattr -d com.apple.quarantine /Applications/Vox.app
   ```

After the first launch, macOS remembers the exemption.

Notarization ($99/yr Apple Developer Program) removes that first-launch friction — skip for now, add later if distributing widely.

### Build from source

```sh
git clone git@github.com:andykumeda/vox.git
cd vox
./scripts/create-dev-cert.sh
./scripts/build-app.sh
open build/Vox.app
```

## Roadmap (not yet)

- Custom vocabulary / personal dictionary
- SSH-vs-local detection inside a terminal
- Streaming transcription
- Separate mode for code editors
- Floating HUD near the cursor
- Homebrew cask
- Notarized releases
- Per-call output token cost tracking (currently estimate is audio-only)
- Mode toggle hotkey (instead of Settings checkbox for prose override)
