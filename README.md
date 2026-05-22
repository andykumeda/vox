# Vox

Push-to-talk voice dictation for macOS (Apple Silicon). Hold **Fn**, speak, release — Vox transcribes via OpenAI and pastes at the cursor in whichever app has focus. Also includes a meeting-transcription mode (system audio + your mic in parallel), a personal dictionary, and an opt-in LLM cleanup pass.

Default transcription model is `gpt-4o-mini-transcribe`. Switchable to `gpt-4o-transcribe` (best quality) or `whisper-1`.

## Modes

Vox runs in one of two text-shaping modes:

- **Prose** — capitalizes sentence starts, ensures a space after `.`, `!`, `?`, detects questions, and synthesizes a Space keystroke for inter-sentence separation.
- **Command** — no auto-capitalize, no trailing period, aggressive number-to-digit conversion, spoken-punctuation expansion (`dash`, `dot`, `pipe`), NATO phonetic letters after dashes, and trailing-keyword key-event synthesis (`tab`, `return`, `escape`, `control X`).

Mode is auto-selected by the frontmost app: terminals (`Terminal.app`, `iTerm2`, `Warp`, `Ghostty`, `Alacritty`, `kitty`, `WezTerm`, `Hyper`, `Wave`, `Tabby`) → command; everything else → prose. Override via Settings → Mode (`auto` / `always prose` / `always command`) or the **mode-toggle hotkey** (default `⌃⌥M`).

## Requirements

- macOS 13+ on Apple Silicon (M1/M2/M3/M4).
- Xcode 16+ command-line tools (`xcode-select --install`) — ships with Swift 6.
- An [OpenAI API key](https://platform.openai.com/api-keys).
- `git` (preinstalled on macOS).
- *Watch out:* if Homebrew OpenSSL 3 is on `PATH` ahead of `/usr/bin/openssl`, `create-dev-cert.sh` may fail with `MAC verification failed` during the PKCS#12 import. The script pins `/usr/bin/openssl` internally; if you still see it, run `which openssl`.

## Quick start

End-to-end from a fresh Mac:

```sh
xcode-select --install                          # if not already installed
git clone https://github.com/andykumeda/vox.git
cd vox
./scripts/setup.sh
```

`setup.sh` is idempotent. Preflight checks (Xcode tools, Swift, `/usr/bin/openssl`, `security` CLI, arch), creates the `vox-dev` self-signed identity if missing (prompts for **login keychain password**), builds, kills any old running Vox, launches the new build, prints the permission-grant checklist.

Then:

1. Grant **Microphone**, **Input Monitoring**, **Accessibility** when macOS prompts (or in System Settings → Privacy & Security if a prompt was missed). Meeting transcription also needs **Screen Recording**.
2. Click the menu-bar Vox icon → **Settings** → paste OpenAI API key → **Save** → click **Always Allow** on the keychain prompt.
3. Hold **Fn**, speak, release.

## Updating

Vox ships in-app updates via **Sparkle**. Click the menu-bar icon → **Check for Updates…**, or wait for the daily auto-check. Releases are ad-hoc-signed, so each update drops Microphone / Input Monitoring / Accessibility grants — re-grant in System Settings → Privacy & Security after Sparkle reinstalls. See [docs/UPDATING.md](docs/UPDATING.md) for the manual fallback.

## Manual build

```sh
./scripts/create-dev-cert.sh   # ONE TIME — persistent self-signed identity
./scripts/build-app.sh
open dist/Vox.app
```

`create-dev-cert.sh` creates a self-signed `vox-dev` identity in the login keychain. Signing every build with the same identity keeps macOS **TCC permissions sticky across rebuilds**. Skip it and the build falls back to ad-hoc signing — every rebuild revokes Accessibility / Input Monitoring / Microphone, forcing re-permit.

`build-app.sh` probes for the `vox-dev` identity in two phases: (a) `find-identity -v -p codesigning` against the default search list, then (b) the login keychain alone (MDM-managed Macs where the cert can't reach System trust). Designated requirement is pinned to the cert SHA so Keychain ACLs don't re-prompt every rebuild.

Always launch via `open`, not by running the binary directly:

```sh
open dist/Vox.app
```

Running `./dist/Vox.app/Contents/MacOS/vox` from a shell makes the process a child of the terminal, and TCC attributes Accessibility grants to the terminal instead of Vox — paste silently fails.

## Hotkeys

Settings → Hotkeys lets you rebind:

| Hotkey | Default | Trigger | Purpose |
|---|---|---|---|
| Record dictation | `Fn` | press-and-hold | hold to record, release to transcribe + paste |
| Mode toggle | `⌃⌥M` | tap | flip between prose ↔ command (skips `.auto`) |
| Meeting panel | `⌃⌥⇧M` | tap | toggles the floating Meeting Record/Stop panel |
| Paste last transcription | *(disabled)* | tap | re-pastes the most recent dictation. Pick a combo to enable. |

Press-and-hold can be flipped to **tap-toggle** for the record hotkey.

Hold **Option while pressing the record hotkey** to dictate **verbatim** — skip cleanup + trigger expansion, paste raw transcription.

## Verbatim / literal

Two ways to bypass Smart Cleanup for a single dictation:

- **Hold Option + record hotkey** — that recording is pasted raw.
- **Say "verbatim" or "literal" as the first word.** The prefix is stripped, the rest is pasted as Whisper transcribed it. Example: speaking *"verbatim he literally said um maybe yeah"* pastes `he literally said um maybe yeah`.

## Settings

Click the menu-bar Vox icon → **Settings**:

- **OpenAI API key** — stored in the macOS Keychain (`com.andykumeda.vox` / `openai-api-key`). Click **Always Allow** on the keychain prompt the first time.
- **Model** — `gpt-4o-mini-transcribe` (~$0.003/min, default), `gpt-4o-transcribe` (~$0.006/min, best quality), or `whisper-1` (~$0.006/min, no prompt-following).
- **Usage (lifetime)** — calls, audio minutes, words, USD estimate. Refresh + Reset buttons. Estimate = `audioMinutes × model.usdPerMinute`.
- **Mode override** — `Auto (detect by app)` / `Always prose` / `Always command`.
- **Smart cleanup** — opt-in LLM polish via gpt-4o-mini removes obvious false starts, fillers, and self-corrections in prose. The personal cleanup instructions editor is saved at `~/Library/Application Support/Vox/cleanup-profile.md`; leave it empty for default behavior. Bypassed by verbatim modifier or "verbatim"/"literal" prefix word.
- **Meeting mode** — enable the meeting panel and Screen Recording capture. Includes a consent acknowledgement (you must inform participants before recording).
- **Recordings storage** — retention cutoff for raw audio (forever / 1y / 3mo / 1mo / 7d). Transcripts are kept indefinitely. Reveal-in-Finder buttons + live disk usage.
- **Dictation history** — retention cutoff for transcript history (forever / 1y / 90d / 30d).
- **Paste behavior** → **Keep transcription on clipboard after paste** — on by default. When on, transcribed text remains on your clipboard so you can paste again if focus moved away. When off, prior clipboard contents are restored ~1.5s after paste; restore is skipped if anything else writes to the clipboard in the meantime. Screen Sharing/VNC targets keep the transcript on the local clipboard to avoid remote pasteboard lag reading stale manual clipboard contents.
- **Hotkeys** — rebind any of the four hotkeys (see table above).

## Dictionary

Settings → **Dictionary** lets you define custom substitutions:

- Spoken `vox` → replacement `Vox` (proper-noun fix in prose).
- Spoken `next field` → replacement `next tab` to insert "next" + Tab key.
- Mode scope: command, prose, or both.
- "Match only at start" anchors to the first word of an utterance.

12 built-in fixups are active behind the scenes (e.g. `ls -shell` → `ls -l`). To silence one: **Reveal in Finder**, edit `dictionary.json`, set `"enabled": false`. Reloads automatically.

A replacement that ends with one of these words fires that key after pasting:

- `tab` — Tab (needs at least one preceding word)
- `return`, `enter`, `newline` — Return
- `escape`, `esc` — Esc
- `control X` — Ctrl+X (any letter)

## Meeting transcription

Vox transcribes meetings end-to-end by capturing **system audio** (Zoom/Meet/etc, via ScreenCaptureKit) and your **local mic** in parallel.

- Press the meeting hotkey (default `⌃⌥⇧M`) or pick **Meeting** from the menu bar to open the floating panel.
- Click the green **Record** disc to start. Click the red **Stop** square to end.
- Closing the panel with `X` only hides the UI — recording continues. Re-open the panel via hotkey or menu to see the running timer or stop.
- On Stop, Vox transcribes via the configured provider:
  - **Deepgram Nova-3 (default if a Deepgram key is set)** — mic + system audio are mixed into a single composition aligned by wall-clock and submitted in one batch request with `diarize=true`. Returns segments tagged with `Speaker 0 / 1 / 2 …` so individual participants are distinguished within the system-audio stream instead of being collapsed under a single "Remote" label.
  - **OpenAI Whisper (fallback)** — mic and system streams are chunked, transcribed independently, and tagged `You` (mic) vs `Other` (system). No within-stream speaker separation.
  Provider is selectable in Settings → Meeting. Add a Deepgram API key in Settings → Deepgram API key (Keychain account `deepgram-api-key`).
- Meeting audio + transcripts persist at `~/Library/Application Support/Vox/MeetingTranscripts/<id>/`. Audio is auto-purged per Settings → Recordings storage; transcripts kept forever.
- Each meeting in the transcript browser has a **Re-transcribe (Deepgram)** button that reruns an existing meeting through Deepgram using the retained audio on disk, replacing the segments + summary in place. Useful for rescuing meetings transcribed before 0.7.0.

Permissions: **Screen Recording** (system audio + window-title polling for auto-detect), **Microphone** (local stream).

The mic recorder runs a per-second peak-power watchdog so a stalled OS-level audio input (Teams renegotiating, USB power management, exclusive-access contention) self-recovers. After 30 s of consecutive floor-level silence the watchdog tears down the recorder, archives the part-file, and starts a fresh one writing to the original output URL. At stop, parts are concatenated via AVMutableComposition into a single m4a so the chunking pipeline is unchanged.

### Auto-show panel when a call starts (opt-in)

Settings → Meeting → **Auto-show meeting panel when a call starts**. Vox polls window titles every ~3 seconds and pops the floating Meeting panel as soon as it sees a known meeting in progress:

- Teams desktop (`Meeting in`, `Meeting with`, `Meeting compact view`, `Call with`, `(Meeting)`)
- Zoom desktop (`Zoom Meeting`, `Zoom Webinar`)
- Webex desktop (`Webex Meeting`, `Webex Personal Room`)
- Slack huddle, Discord voice/video, Skype call
- Web meetings: Google Meet, Zoom web, Webex web, Teams web (active tab in Chrome / Safari / Edge / Arc / Brave / Firefox)

Recording is **never** auto-started — the user still clicks Record on the panel. Detection requires Screen Recording permission so `CGWindowListCopyWindowInfo` can return window titles. To debug detection, run `swift scripts/dump-windows.swift` from terminal (note: terminal-launched scripts will see empty titles unless you grant Terminal Screen Recording too).

### Meeting summary (opt-out)

Settings → Meeting → **Generate meeting summary after transcription** (default ON). After Vox finishes transcribing, segments are sent to gpt-4o-mini with a structured prompt; the markdown summary (Summary / Key decisions / Action items) is stored on the transcript and rendered in a disclosure section at the top of the transcript browser. Cost is ~$0.0005 per meeting. If the API key is missing or the call fails, summary is silently skipped — the transcript still works.

## Menu bar icon

| State | Icon | Color |
|---|---|---|
| Idle (prose) | chrome-V on squircle | cyan/teal |
| Idle (command/terminal) | chrome-V on squircle | amber/gold |
| Recording | V with red dot badge | — |
| Transcribing | V with orange dot badge, pulsing | — |
| Meeting recording | filled record circle | red, pulsing |
| Meeting transcribing | waveform circle | orange, pulsing |
| Error | exclamationmark.triangle | template |

The orange macOS recording indicator dot also appears whenever Vox holds the mic — that's a system privacy feature.

The status menu has entries for Home, Meeting, Dictionary, **Paste Last Transcription**, Settings, Check for Updates, Help, Quit. Paste-last is disabled when no history exists.

Remote desktop apps need special paste handling. macOS Screen Sharing/VNC uses a System Events paste fallback when Vox is frontmost over the remote session and keeps the transcript on the local clipboard so VNC pasteboard sync does not consume the previous manual clipboard value. RustDesk drops synthetic modifier keys, so Vox falls back to typing the transcript as plain physical keypresses; letters may be lowercased and shifted punctuation may be approximated, but the text should still reach the remote cursor. Paste Last Transcription uses the same path.

## Files

- Dictionary: `~/Library/Application Support/Vox/dictionary.json`
- Smart cleanup profile: `~/Library/Application Support/Vox/cleanup-profile.md`
- Dictation history: `~/Library/Application Support/Vox/DictationHistory/history.json`
- Dictation recordings: `~/Library/Application Support/Vox/Recordings/`
- Meeting transcripts + audio: `~/Library/Application Support/Vox/MeetingTranscripts/`
- Logs: `~/Library/Logs/vox.log`

## Log file

```sh
tail -f ~/Library/Logs/vox.log
```

Lines: Fn press/release, AVAudioEngine state, WAV byte counts + RMS + duration, raw API response, post-processor output (text + suffixKeys + word count + cost estimate), hallucination-guard hits, meeting session lifecycle.

## Project layout

```
Package.swift            swift-tools-version 6.0, macOS 13+, Swift 5 language mode
Resources/               Info.plist, vox.entitlements, AppIcon.icns, help.md, AppIcon variants
scripts/
  setup.sh               One-shot bootstrap (idempotent)
  create-dev-cert.sh     One-time: persistent "vox-dev" code-signing identity
  build-app.sh           Builds release binary, wraps as .app, codesigns
  generate-icon.sh       Renders AppIcon.icns from Swift + sips + iconutil
  generate-icon.swift    SF Symbols on gradient → 1024×1024 PNG
  make-dmg.sh            Drag-to-Applications DMG packager
  run-dictation-regression.sh  Runs the dictation regression suite
Sources/vox/
  App/                   AppDelegate, MenuBarController (icon/state machine), MainWindow, SettingsWindow, MeetingHUDPanel, MeetingTranscriptsWindow, HelpWindow
  Audio/                 AudioRecorder — AVAudioEngine → 16 kHz mono 16-bit WAV (streamed to disk)
  Context/               ContextDetector — NSWorkspace frontmost → prose/command
  Hotkey/                Hotkey, HotkeyMonitor (CGEventTap), HotkeyRecorder (NSEvent capture for Settings UI)
  Meeting/               MeetingTranscriptionSession, MeetingMicCapture, ScreenCaptureKit system-audio tap, SilenceTrim, MeetingChunker, MeetingTranscriptStore, MeetingPreflight
  STT/                   OpenAITranscriber, TranscriptionMode (per-mode prompt), hallucination guards
  Text/                  PostProcessor, NumberNormalizer, CleanupProcessor (LLM + triggers + verbatim/literal prefix), CleanupDictionaryProtection, TextInjector (paste + sendKey)
  Util/                  KeychainStore, SoundPlayer, AppSettings, UsageTracker, DictationHistoryStore, RecordingArchive, CleanupProfileStore, DictionaryStore + DictionaryMatcher, Log
docs/
  appcast.xml            Sparkle update feed (served via GitHub Pages)
  UPDATING.md            Update procedure (auto + manual fallback)
  dictation-regression.md  Regression-suite policy + thresholds
  index.html             Pages landing
Tests/voxTests/          302 unit tests covering text pipeline, hotkey, meeting, retention, history
```

## Testing

```sh
swift test
```

Dictation regression with merge-blocking thresholds:

```sh
./scripts/run-dictation-regression.sh
```

See [docs/dictation-regression.md](docs/dictation-regression.md) for thresholds and CI gating.

## Releasing

The Sparkle EdDSA private key for signing updates lives **on the kumedaa Dev workstation** (this Mac). Releases must be cut from there.

```sh
# 1. Bump CFBundleShortVersionString + CFBundleVersion in Resources/Info.plist
# 2. Build + sign DMG
./scripts/make-dmg.sh
.build/artifacts/sparkle/Sparkle/bin/sign_update dist/Vox.dmg
# → prints sparkle:edSignature="…" length="…"

# 3. Add a new <item> to docs/appcast.xml at the top, with the signature/length above
# 4. Commit, tag, push
git add Resources/Info.plist docs/appcast.xml
git commit --no-gpg-sign -m "release: 0.X.Y — …"
git tag v0.X.Y
git push origin main && git push origin v0.X.Y

# 5. Publish GitHub release with the DMG attached
gh release create v0.X.Y --title "Vox 0.X.Y" --notes "…" dist/Vox.dmg
```

GitHub Pages serves `docs/appcast.xml` at `https://andykumeda.github.io/vox/appcast.xml` (the `SUFeedURL` in `Info.plist`). Pages must remain enabled — disabling it breaks Sparkle for every existing install.

DMG asset URL is `https://github.com/andykumeda/vox/releases/download/v<version>/Vox.dmg`. The repo must remain **public** for anonymous Sparkle download; private repos block unauthenticated asset fetches.

### First-launch on another Mac (no Sparkle)

The DMG is **self-signed**, not Apple-notarized. Gatekeeper will say *"Vox.app cannot be opened because Apple cannot check it for malicious software."* Bypass once:

1. Right-click **Vox.app** in `/Applications` → **Open** → **Open Anyway**, or
2. From Terminal: `xattr -d com.apple.quarantine /Applications/Vox.app`.

After the first launch, macOS remembers the exemption.

## Roadmap (not yet)

- Meeting summarization (TL;DR via gpt-4o-mini after each meeting transcript completes)
- SSH-vs-local detection inside a terminal
- Streaming transcription
- Separate mode for code editors
- Floating HUD near the cursor
- Homebrew cask
- Notarized releases (removes Gatekeeper friction + makes TCC grants persist across updates)
- Per-call output token cost tracking (currently estimate is audio-only)
- Mission Control space-switcher via synthesized arrow keystrokes (currently filtered by macOS — needs Developer ID + notarization)
