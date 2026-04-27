# Handoff — Vox state as of 2026-04-25

For the next Claude session (or human dev) picking this up. Read once, then act.

> User prefers terse, fragment-style responses (caveman mode). Drop articles, pleasantries, hedging. Code blocks unchanged.

## What Vox is

macOS Apple-Silicon push-to-talk dictation app. Hold Fn → record → OpenAI transcription → paste at cursor. Two modes (prose / command, chosen by frontmost-app bundle ID). Menu-bar app (`LSUIElement=true`), no Dock icon. Repo: [github.com/andykumeda/vox](https://github.com/andykumeda/vox). Full feature docs in `README.md`.

## Current state

Working. Push-to-talk → paste cycle is reliable. Tests: 79 passing.

### What ships in command mode

- Aggressive number-to-digit conversion (`head -n three` → `head -n 3`)
- Joined-flag splitting (`ls-l` → `ls -l`)
- Spoken punctuation: `dash`/`minus` → `-`, `double dash` → `--`, `dot` → `.`, `pipe` → `|`
- NATO phonetic letters after `-`/`--` (`dash lima` → `-l`, `minus romeo foxtrot` → `-rf`)
- Trailing-keyword key-event synthesis: `tab`, `return`/`enter`/`newline`, `escape`/`esc`, `control X`/`ctrl X`
- Bare `return`/`enter`/`escape`/`control X` fire alone (no preceding text required)
- Bare `tab` stays as text (too risky — could be filename arg)

### What ships in prose mode

- Capitalize sentence starts
- Question detection — sentences starting with `is/are/was/were/do/does/did/have/has/will/would/should/can/could/may/might/must/who/what/when/where/why/how/whose/which/shall` get `?` not `.`
- Discrete Space keypress after paste (Wave terminal and similar strip trailing whitespace from pasted text)
- URL/domain/IP/version/filename shielding from sentence-splitting
- Single-digit number words stay as words (compound numbers convert)

### Settings

- Model picker: `gpt-4o-mini-transcribe` (default, ~$0.003/min), `gpt-4o-transcribe` (~$0.006/min), `whisper-1` (~$0.006/min, no prompt-following)
- Lifetime usage tracking: calls, audio sec, words, USD estimate (UserDefaults-backed)
- "Always use prose mode" toggle — overrides terminal context detection
- "Keep transcription on clipboard after paste" toggle

### Menu bar icon

`text.bubble` (idle) → `text.bubble.fill` red (recording) → `text.bubble.fill` orange pulsing (transcribing) → `exclamationmark.triangle` (error). Implemented via SF Symbol palette config (NSStatusBarButton's `contentTintColor` is unreliable in menubar). Pulse is a manual `Timer` since `addSymbolEffect` requires macOS 14+ and the package targets macOS 13.

## Known gotchas (don't relearn the hard way)

- **Always launch via `open`, never the binary directly.** Direct invocation makes Vox a child of Terminal; TCC attributes Accessibility to the terminal and paste silently fails.
- **Fn key may not fire** if "Press 🌐 key to" is set to anything other than *Do Nothing* in System Settings → Keyboard. macOS intercepts before our `CGEventTap` sees it.
- **First-time API key save** triggers a Keychain prompt. Click **Always Allow** (not "Allow") — otherwise it re-prompts every launch.
- **Keychain re-prompt after switching from ad-hoc to vox-dev signing** is expected once. ACL was pinned to ad-hoc CDHash; first save under vox-dev re-pins to the new identity (locked by the build's designated requirement).
- **Self-relocator** triggers when running from `/Volumes/*` or `~/Downloads/*`. Running from `~/Applications/*` or `/Applications/*` is silent. Running from `~/Dev/vox/dist/Vox.app` does NOT trigger relocation.
- **MDM-managed Macs** can't write `/Library/Keychains/System.keychain` even with sudo. `build-app.sh` falls back to probing the login keychain alone (no `-v`) when the default-search-list probe finds nothing.
- **`find-identity -v` (no `-p`) returns 0 valid identities** — must use `-p codesigning`. The build script has both.
- **Pipefail + `grep -q`** killed an earlier identity probe (SIGPIPE). Current probe uses an intermediate variable. Don't reintroduce the inline pipe.
- **NSStatusBarButton `contentTintColor` is unreliable** for tinting template images in the menubar. Use SF Symbol palette config instead and set `isTemplate = false`.
- **Wave terminal strips trailing whitespace on paste.** Prose mode now sends a discrete Space keypress instead of relying on a trailing space in the pasted string.
- **macOS 14+ orange recording indicator** appears whenever Vox holds the mic. Privacy feature, can't suppress without lower-level Core Audio APIs. Documented in README.

## Architecture quick map

```
Fn keydown  → HotkeyMonitor.onPress  → MenuBarController.beginRecording
                                           → AudioRecorder.start()
                                           → state = .recording (red bubble)
Fn keyup    → HotkeyMonitor.onRelease → MenuBarController.endRecordingAndTranscribe
                                           → AudioRecorder.stop() returns WAV
                                           → silence gate (skip if too short/quiet)
                                           → state = .transcribing (orange pulse)
                                           → OpenAITranscriber.transcribe(wav, mode)
                                           → PostProcessor(mode).process(raw)
                                                   → trim / collapse whitespace
                                                   → NumberNormalizer (mode-aware)
                                                   → URL/filename shielding
                                                   → ensureSpaceAfterSentenceEnd
                                                   → mode branch:
                                                       prose: capitalize, question detect, terminator
                                                              → suffixKeys = [.space]
                                                       command: lowercase, strip term, expand spoken punct,
                                                                NATO expand, splitCommandFromFlag,
                                                                extractTrailingSuffixKeys
                                                   → restoreURLs
                                           → TextInjector.paste(text)
                                           → for each suffixKey: TextInjector.sendKey(key) (staggered)
                                           → UsageTracker.record(...)
                                           → state = .idle
```

## Files most likely to touch next

| Path | Why |
|---|---|
| `Sources/vox/Text/PostProcessor.swift` | All text-transform rules — most behavior changes land here |
| `Sources/vox/Text/NumberNormalizer.swift` | Number-word → digit logic |
| `Sources/vox/Text/TextInjector.swift` | `SuffixKey` enum + key-event synthesis |
| `Sources/vox/STT/TranscriptionMode.swift` | Whisper prompts per mode |
| `Sources/vox/App/MenuBarController.swift` | State machine, icon refresh, paste/key dispatch |
| `Sources/vox/App/SettingsWindow.swift` | SwiftUI settings — model picker, usage panel, mode toggle |
| `Sources/vox/Util/AppSettings.swift` | UserDefaults-backed settings + `TranscriptionModel` enum |
| `Sources/vox/Util/UsageTracker.swift` | Lifetime usage totals |
| `scripts/build-app.sh` | Identity probe (System keychain via `-v -p codesigning`, fallback to login) |
| `scripts/create-dev-cert.sh` | Generates `vox-dev` self-signed cert |

## Suggested next-phase work

Loose backlog, ordered roughly by user value × ease:

### Quick wins

1. **Strip trailing punctuation from prefix word before `tab`.** Whisper sometimes inserts `.` mid-text: `brew upd. tab` → currently pastes `brew upd.` then sends Tab → shell tries to complete `upd.` → fails. Fix: in `extractTrailingSuffixKeys`, strip trailing `,.!?` from the new last word after stripping a `tab` keyword.
2. **Mode toggle hotkey.** Currently the "Always use prose mode" toggle lives in Settings — clunky if user switches contexts often. Add a global hotkey (e.g., Cmd+Opt+P) that flips it from anywhere.
3. **Spoken-punctuation expansion to prose mode** for things like "comma" → ",", "period" → "." (within prose), "open paren" → "(". Currently command-mode only.
4. **Per-call output token cost.** UsageTracker estimate is audio-input only. OpenAI bills tiny extra for output tokens. Capture token count from response (gpt-4o models return it) and add to lifetime cost.
5. **Visual cue for force-prose mode active.** Currently no indication. Maybe a small dot on the bubble icon when override is on.

### Medium

6. **Per-app mode override.** Settings list: `bundle ID → forced mode`. So Vim could be forced to command mode even though it's not in the terminal list. Or Slack could be forced to prose with no auto-question detection (annoying for chat).
7. **Streaming transcription.** OpenAI now supports realtime; would let the bubble show partial text as user speaks. Bigger refactor (URLSession streaming + incremental paste).
8. **Custom vocabulary.** Lets the user inject their own names / terms into the Whisper prompt. Settings field, saved to UserDefaults.
9. **Better question detection.** Current heuristic is "first word matches list". Misses "Is the door open or closed", catches "Is" inverted statements that aren't questions ("Is fine, thanks"). Could use prosody hints from API if available, or ML.
10. **DMG release pipeline.** `make-dmg.sh` exists but no GitHub Actions. Add CI that builds + signs + uploads on tag push.

### Bigger

11. **SSH-vs-local detection inside a terminal.** Useful: when SSHed into a remote box, command-mode might behave differently (e.g., Linux flag conventions vs macOS).
12. **Code-editor mode.** VS Code / Xcode / Cursor / etc. — different formatting needs (no auto-period, comments vs code, etc.).
13. **Floating HUD near the cursor.** Show recording state + partial transcription near where the cursor is, not just menubar.
14. **Notarization.** $99/yr Apple Developer; removes Gatekeeper friction for distribution.

## Testing

```sh
swift test                # 79 tests, ~30ms
./scripts/build-app.sh    # ~5s incremental, 60s clean
```

If you see `precompiled file ... was compiled with module cache path '/Users/andy/Dev/stt/...'` errors, the repo was renamed from `stt` → `vox` historically and module cache is stale. Fix: `rm -rf .build`.

## After you change things

If functional code change:
```sh
swift test                              # confirm no regressions
./scripts/build-app.sh                  # rebuild
pkill -f 'Vox.app/Contents/MacOS/vox'   # kill old instance
open dist/Vox.app                      # relaunch
tail -f ~/Library/Logs/vox.log          # verify behavior live
```

Push to main (no PR workflow):
```sh
git add -A
git commit -m "feat: ..."
git push
```

User is `andykumeda`. SSH auth works. Remote is `origin/main`.

If only configuration / docs change, update this `HANDOFF.md` with what changed before signing off.
