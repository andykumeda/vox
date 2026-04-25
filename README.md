# Vox

Push-to-talk voice dictation for macOS (Apple Silicon). Hold **Fn** to speak, release to transcribe with OpenAI's `gpt-4o-transcribe`. Output is pasted at the cursor in whichever app has focus.

Context-aware: when the frontmost app is a terminal (`Terminal.app`, `iTerm2`, `Warp`, `Ghostty`, `Alacritty`, `kitty`, `WezTerm`, `Hyper`, `Wave`), Vox switches to **command mode** — no auto-capitalize, no trailing period, Whisper prompted with common shell vocabulary. Otherwise, **prose mode** — capitalizes sentence starts, ensures a space after `.`, `!`, `?`, and appends a terminal period + trailing space if missing.

## Requirements

- macOS 13+ on Apple Silicon
- Xcode 16+ command-line tools (`xcode-select --install`) — ships with Swift 6
- An [OpenAI API key](https://platform.openai.com/api-keys) (`gpt-4o-transcribe`, ~$0.006/minute)

## Build

```sh
./scripts/create-dev-cert.sh   # ONE TIME — persistent self-signed identity
./scripts/build-app.sh
open build/Vox.app
```

`create-dev-cert.sh` creates a self-signed `vox-dev` identity in the login keychain. Signing every build with the same identity keeps macOS **TCC permissions sticky across rebuilds**. Skip it and the build falls back to ad-hoc signing — but then every rebuild revokes Accessibility / Input Monitoring / Microphone grants, forcing you to re-permit.

The first build also generates `Resources/AppIcon.icns` from `scripts/generate-icon.swift` (blue→purple gradient with SF Symbols `mic.fill`). Replace `Resources/AppIcon.png` and re-run `scripts/generate-icon.sh` to customize.

## Launch

Always launch via `open`, not by running the binary directly:

```sh
open build/Vox.app
```

Running `./build/Vox.app/Contents/MacOS/vox` from a shell makes the process a child of the terminal, and TCC attributes Accessibility grants to the terminal instead of Vox — the paste keystroke will silently fail.

### First-run permissions

macOS will prompt three times. Grant each:

1. **Microphone** — required to record audio.
2. **Input Monitoring** — required for the `CGEventTap` that watches the Fn key.
3. **Accessibility** — required to synthesize Cmd+V into the focused app.

If Fn doesn't trigger: **System Settings → Keyboard → "Press 🌐 key to"** → set to *Do Nothing* (or rebind), otherwise macOS intercepts Fn for the emoji/dictation picker.

### Settings

Click the menu bar mic icon → **Settings…**

- **OpenAI API key** — stored in the macOS Keychain (`com.andykumeda.vox` / `openai-api-key`). Click **Always Allow** on the keychain prompt the first time.
- **Keep transcription on clipboard after paste** — when on, the transcribed text remains on your clipboard so you can Cmd+V again if focus moved. When off (default), your prior clipboard is restored ~400 ms after paste.

## Usage

Hold **Fn**, speak, release. The menu bar icon goes red while recording, animates while transcribing, then pastes the result at the cursor.

### Post-processing rules

- Trims and collapses whitespace.
- Ensures a single space after `.`, `!`, `?`.
- Rewrites spelled-out numbers as digits (`twenty-three` → `23`, `two thousand five hundred` → `2500`).

**Prose mode** (default): capitalizes the first letter of each sentence; appends `.` plus a trailing space if the utterance didn't end with one.

**Command mode** (terminal frontmost): lowercases a mis-capitalized first letter, strips trailing `.!?`, leaves flags like `--verbose` and `-la` untouched, no trailing space.

### Silence gate

Empty or very quiet recordings are dropped before hitting the transcription API. Speech models tend to hallucinate or echo the system prompt when given silence, so Vox requires at least ~0.35 s of audio and a minimum RMS.

## Log file

Vox always appends to `~/Library/Logs/vox.log`:

```sh
tail -f ~/Library/Logs/vox.log
```

You'll see Fn press/release, WAV byte counts, API responses, and post-processor output.

## Project layout

```
Package.swift            swift-tools-version 6.0, macOS 13+, Swift 5 language mode
Resources/               Info.plist, vox.entitlements, AppIcon.icns
scripts/
  build-app.sh           Builds release binary, wraps as .app, codesigns
  create-dev-cert.sh     One-time: creates stable "vox-dev" code-signing identity
  generate-icon.sh       Renders AppIcon.icns from Swift + sips + iconutil
  generate-icon.swift    SF Symbols mic.fill on gradient → 1024×1024 PNG
Sources/vox/
  App/                   AppDelegate, MenuBarController, SettingsWindow (SwiftUI)
  Audio/                 AudioRecorder — AVAudioEngine → 16 kHz mono 16-bit WAV
  Context/               ContextDetector — NSWorkspace frontmost → prose/command
  Hotkey/                HotkeyMonitor — CGEventTap on Fn (kCGEventFlagMaskSecondaryFn)
  STT/                   OpenAITranscriber, TranscriptionMode
  Text/                  PostProcessor, NumberNormalizer, TextInjector
  Util/                  KeychainStore, SoundPlayer, AppSettings
Tests/voxTests/          Unit tests for PostProcessor, NumberNormalizer, ContextDetector
```

## Testing

```sh
swift test
```

31 unit tests cover the text-transform pipeline and context detection.

## Distribution

### Build a DMG

```sh
./scripts/make-dmg.sh
# → dist/Vox.dmg (drag-to-Applications installer)
```

Open the DMG, drag **Vox.app** onto the **Applications** alias. No admin password required for users in the `admin` group (Finder's drag-drop path, unlike `cp` from Terminal which sometimes triggers auth).

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

After the first launch, macOS remembers the exemption. Later launches open normally.

Notarization ($99/yr Apple Developer Program) removes that first-launch friction — skip for now, add later if distributing widely.

### Build from source (alternative)

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
- Homebrew cask / DMG
- Notarized releases
