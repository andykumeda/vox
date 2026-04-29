# Handoff — Vox state as of 2026-04-28 (PM)

## Session 2026-04-28 — STT bench, Smart Cleanup, command-mode bug fixes, mode-override tri-state, arrow+modifier keys, dictionary punct fix

**Context:** Long session covering one new exploratory tool (STT provider benchmark), one major user-facing feature (Smart Cleanup with LLM polish + trigger phrases), three command-mode bug fixes, a settings model change, and a couple smaller features. All work landed on `feat/smart-cleanup` (the integrated test branch). Standalone fix branches exist for clean cherry-picking.

### What shipped

#### 1. STT provider benchmark — `feat/stt-bench` and `tools/stt-bench/`

Standalone Python CLI benchmarking OpenAI gpt-4o-transcribe vs Deepgram Nova-3 vs AssemblyAI Universal-2 on 13 prose samples (10 clean + 3 noise-mixed via ffmpeg). Spec: `docs/superpowers/specs/2026-04-28-stt-bench-design.md`. Plan: `docs/superpowers/plans/2026-04-28-stt-bench.md`. Run findings recorded in `tools/stt-bench/README.md` "Bench run history".

**Verdict:** No clear accuracy winner over current OpenAI. Pain B (real-speech mishears, esp. names) is shared across the entire Whisper family — switching providers won't materially fix it. Pain A (silent-input hallucinations) only OpenAI exhibits; Deepgram and AssemblyAI return empty. Deepgram is a viable tradeoff candidate (28% cheaper, 3× faster, no silent-input hallucinations) at small accuracy cost — flagged for a future Vox-integration spec.

API keys live in `tools/stt-bench/.env` (gitignored). Branch is unmerged but mergeable independently of everything else.

#### 2. Smart Cleanup (prose mode) — `feat/smart-cleanup`

Spec: `docs/superpowers/specs/2026-04-28-smart-cleanup-design.md`. Plan: `docs/superpowers/plans/2026-04-28-smart-cleanup.md`.

Opt-in cleanup pass between `PostProcessor` and `TextInjector`. Two layers:

- **Three deterministic triggers** (regex + sentence tokenizer for prose; substring for command):
  - `scratch that` / `delete that` → wipe preceding clause
  - `new paragraph` → `\n\n`
  - `new line` → `\n`
- **LLM polish via OpenAI gpt-4o-mini** in prose mode only. 5s timeout, fail-open. Removes false starts, fillers (um/uh), and self-corrections.

Settings: new `smartCleanupEnabled: Bool` (default false).

**Layered fixes for issues caught during smoke testing:**
- Initial paragraph behavior was broken because gpt-4o-mini stripped `\n\n` as artifacts. Tried placeholder swap (`<<VOX_PARA>>` / `<<VOX_LINE>>`) but the model still strips them. Final fix: skip the LLM call entirely when triggered text contains `\n` — the user dictated an explicit break and gets it; LLM polish is sacrificed for that one dictation.
- Initial command-mode triggers depended on macOS sentence tokenizer, which fails on no-punctuation input (Whisper's command-mode prompt forbids trailing punctuation, so output is one continuous string). Replaced with substring-based "split on trigger, keep what's after the LAST occurrence" semantics for command mode. Prose mode keeps sentence-tokenizer anchoring (lower false-positive risk).

Files: `Sources/vox/Text/CleanupProcessor.swift` (new, ~165 LOC), `Sources/vox/Text/CleanupLLMClient.swift` (new, ~90 LOC, no unit tests per `OpenAITranscriber` precedent), wiring in `MenuBarController.swift`, toggle in `SettingsWindow.swift`. 36 unit tests in `CleanupProcessorTests.swift`.

#### 3. Command-mode: `cd ..` and `./path` — `fix/cd-dot-dot`

User reported `cd dot dot` pasted as `cd .` (one dot). Root cause: `stripTrailingSentencePunctuation` was iterative and ate trailing dots before `expandSpokenPunctuation` could process them. Also: Whisper sometimes consolidates `cd dot dot` → `cd dot.`, eating one dot at the source.

Fix: reorder pipeline (expand BEFORE strip), tighten strip to only remove `.` if preceded by alphanumeric (preserves `cd ..` / `find .`), add `\.\s+/` → `./` glue, add `\s+\.\s+\.` → ` ..` collapse, normalize `(?:\s*\.){3,}\s*$` to ` ..` for stray-period artifacts. 7 new tests cover all the Whisper output variants.

#### 4. Tri-state mode override — `feat/mode-override-tristate`

User reported "in journal app, no way to force command mode" (existing `forceProseMode: Bool` only forces prose; ContextDetector defaults journal to prose). Replaced with `ModeOverride: { auto, prose, command }`. Settings has a segmented Picker. Mode-toggle hotkey cycles all 3. Menu-bar icon tint shows current state (label / blue / purple). Backward-compatible migration reads legacy `forceProseMode=true` → `.prose`; absent / false → `.auto`.

#### 5. Hallucination guard

User reported a 3s "proceed with file cleanup" dictation produced 5000+ chars of `rm -rf X rm -rf Y...` cascade — gpt-4o-mini-transcribe runaway. Added a chars-per-second cap in `MenuBarController.swift` after the STT call: `if raw.count > max(160, durationSec * 40) { suppress }`. Logs `hallucination guard: ...` to `~/Library/Logs/vox.log` for diagnostics.

#### 6. Arrow + modifier suffix keys — `fix/arrow-modifier-keys`

`SuffixKey` extended with `.arrow(direction, modifiers: Set<KeyModifier>)`. Spoken vocabulary at end of dictation: control/ctrl, option/opt/alt, command/cmd, shift × left/right/up/down. Multi-modifier combos work (e.g. "command shift right"). `TextInjector.sendKey` dispatches with `CGEventFlags` for in-app shortcuts. **Limitation:** Mission Control's space-switcher (Ctrl+Left/Right) still does NOT respond to synthesized events even after multiple attempts — see "Known limitations" below.

#### 7. Dictionary edge-punctuation fix — `fix/dictionary-edge-punct`

User reported the dictionary worked for the first occurrence of a word in a sentence but missed later ones. Root cause: `DictionaryMatcher.tokenize` split only on whitespace, so `"Andie,"` (with attached comma after sentence-internal punctuation) was a different token than `"Andie"`. Fix: `tokensEqual` now strips edge punct from input token's core before comparing; `replace` preserves leading and trailing punct on output by attaching to first/last replacement tokens. Spoken patterns also have edge punct stripped during preparation so back-compat with explicit-punct entries is preserved. 7 new tests.

#### 8. `^X` caret-letter recognition

Whisper's command-mode prompt names "control C for Ctrl+C", and the model often encodes a spoken "control X" as the literal symbol `^X`. Added a regex check in `extractTrailingSuffixKeys` for trailing `\^[A-Za-z]$` → `.control(letter)`. 3 new tests.

### Known limitations

**Mission Control space-switcher does NOT respond to Vox's synthesized Ctrl+Left/Right.** Multiple injection paths attempted, all failed:
1. Default: `flags = .maskControl` on the keydown/keyup event, posted at `.cghidEventTap` — nothing happens.
2. Sandwich the arrow event between explicit Control keydown/keyup events — still nothing.
3. Switch tap to `.cgAnnotatedSessionEventTap` (where Mission Control hooks) — still nothing.
4. Switch source to `CGEventSource(stateID: .hidSystemState)` to mimic real hardware + 15ms delays around the event — still nothing.

The synthesized events DO work for in-app shortcuts (verified via paste / Ctrl+letter / arrow word-jump in apps that bind it). The filter is specific to system-level shortcuts that route through WindowServer's space-switcher.

Hypothesis: macOS 14+ requires either a Developer ID + notarization or a specific entitlement to inject events that drive Mission Control. The `vox-dev` self-signed cert isn't sufficient. The `Resources/vox.entitlements` file already grants Accessibility + Input Monitoring; adding more without a real Developer ID is unlikely to help.

**User-facing message:** ctrl+arrow with modifiers works for in-app shortcuts (word-jump in shells/editors that bind it, line-end navigation, selection); it does NOT switch desktops via Mission Control. Workaround: physical keys.

### Branch state at end of session

- `main` — base, unchanged from start of session
- `feat/stt-bench` — bench tool (separate, mergeable)
- `feat/smart-cleanup` — INTEGRATED branch with everything below + Smart Cleanup itself. This is what `dist/Vox.app` was built from.
- `fix/cd-dot-dot` — standalone subset (already in feat/smart-cleanup)
- `feat/mode-override-tristate` — standalone subset (already in feat/smart-cleanup)
- `fix/arrow-modifier-keys` — standalone subset (already in feat/smart-cleanup)
- `fix/dictionary-edge-punct` — standalone subset (already in feat/smart-cleanup)

The standalone branches exist so each feature can be merged independently if `feat/smart-cleanup` is too coarse.

### Files touched this session

- New: `tools/stt-bench/` (entire dir), `Sources/vox/Text/CleanupProcessor.swift`, `Sources/vox/Text/CleanupLLMClient.swift`, `Tests/voxTests/CleanupProcessorTests.swift`, three spec docs under `docs/superpowers/specs/`, three plan docs under `docs/superpowers/plans/`
- Modified: `Sources/vox/Util/AppSettings.swift` (smartCleanupEnabled, ModeOverride enum, modeOverride accessor), `Sources/vox/App/MenuBarController.swift` (CleanupProcessor wiring, hallucination guard, mode-override switch), `Sources/vox/App/SettingsWindow.swift` (Smart cleanup toggle, Mode segmented Picker), `Sources/vox/Text/PostProcessor.swift` (cd .. + ./ + arrow+modifier extraction + ^X recognition), `Sources/vox/Text/TextInjector.swift` (arrow case + Mission Control attempts), `Sources/vox/Util/DictionaryMatcher.swift` (edge punct tolerance), `Tests/voxTests/PostProcessorTests.swift` (~20 new tests), `Tests/voxTests/DictionaryMatcherTests.swift` (~7 new tests)

### Testing

`swift test` → 200+ tests, 0 failures. CleanupProcessorTests covers toggle, three trigger types, false positives, mode dispatch, fail-open, small-output guard, placeholder behavior, command-mode substring path. PostProcessorTests covers cd .. variants, ./ glue, arrow+modifier vocabulary, ^X recognition. DictionaryMatcherTests covers edge punct on input, surrounding quotes, repeated word with mixed punct, empty-replacement deletion.

### Memory entries saved this session

- `feedback_no_gpg_sign.md` — durable: pass `--no-gpg-sign` on commits in this repo
- `project_stt_provider_bench_2026-04-28.md` — bench findings, do NOT propose another provider switch without addressing pain B upstream first
- `feedback_subagent_silent_test_rewrites.md` — when dispatching TDD implementer subagents, demand DONE_WITH_CONCERNS rather than silent input rewrites
- `feedback_rebuild_app_for_testing.md` — run `scripts/build-app.sh` after every Swift commit during user testing
- `project_whisper_hallucination_cascades.md` — gpt-4o-mini-transcribe runaway cascades; chars/sec guard in MenuBarController

---

## Session 2026-04-27 PM — hotkey-recorder stabilization, single-key support, menu-bar icon redesign

**Context:** macOS 26.5 (build 25F5058e) shipped breaking changes that surfaced as crashes when configuring hotkeys, and SF Symbols catalog drift (`text.bubble`, `text.bubble.fill`, `lock.bubble.*` resolve to nil) made the menu-bar icon disappear.

### Crashes fixed

1. **`HotkeyRecorder.finish()` PAC trap** — `CGEvent.tapEnable(false)` on an ephemeral CGEventTap PAC-traps inside `SLEventTapEnable → CFMachPortGetContext` on macOS 26. Replaced the entire CGEventTap path with `NSEvent.addLocalMonitorForEvents` (app-local, only fires while Vox is key window — fine for the settings recorder UI). No second tap, no race against the persistent `HotkeyMonitor` tap.
2. **`HotkeyMonitor.stop()` same PAC trap** — fires on every settings save via `reconfigureHotkey()`. Removed `tapEnable(false)`; just `CFRunLoopRemoveSource` + nil refs. The port deallocates on its own when refs drop.
3. **Heap corruption / `objc_retain` x0=2** during settings save — was downstream of the same broken tap teardown. Resolved by 1+2.

### Single-modifier hotkey support

`Hotkey.Key` gained `case modifier(Modifier)` (one of `.command/.control/.option/.shift`). Captures via `flagsChanged`: exactly one modifier flag set, no other mods. `HotkeyMonitor.matches` and the press/release dispatch both treat `.modifier` like `.fn` (flagsChanged-driven). Settings recorder accepts a single Cmd/Opt/Ctrl/Shift press and stores it. Paste hotkey falls back to ⌘V if bound to a bare modifier (no key to synthesize).

### Menu-bar icon

- `text.bubble` returns nil on macOS 26 beta → status item collapsed to zero width / showed `mic.fill` fallback.
- Idle now uses the actual app icon (`NSApp.applicationIconImage`), 18pt, drawn into a fresh `NSImage`. Recording / transcribing keep an SF Symbol with palette tint (`text.bubble.fill` → `bubble.left.fill` → `waveform` → `mic.fill` resolution chain).
- Mode differentiation: command mode (default) renders the bare app icon (intrinsic purple bg); prose mode renders a tinted SF Symbol bubble glyph on transparent bg (currently `.systemBlue` — **TBD: user wants this color changed to something else, decide later**). Toggle via `forceProseMode` UserDefaults key.
- Error state: `exclamationmark.triangle` template + `contentTintColor = .labelColor`. Without the explicit tint, template + nil tint can render invisible on macOS 26.

### Files touched this session

- `Sources/vox/Hotkey/HotkeyRecorder.swift` — full rewrite: `NSEvent.addLocalMonitorForEvents` instead of `CGEvent.tapCreate`. Captures Fn / single modifier / key+modifier combos. Esc cancels.
- `Sources/vox/Hotkey/HotkeyMonitor.swift` — `stop()` no longer calls `CGEvent.tapEnable(false)`. `matches()` and dispatch handle `.modifier` case; mode-toggle path branches by key type.
- `Sources/vox/Hotkey/Hotkey.swift` — added `Key.modifier(Modifier)` case; `isValid` updated.
- `Sources/vox/App/SettingsWindow.swift` — `displayString` renders `.modifier` glyphs (⌘ ⌃ ⌥ ⇧).
- `Sources/vox/App/MenuBarController.swift` — `refreshIcon` rewritten with per-state SF Symbol fallback chains; idle uses app icon for command, tinted bubble for prose; explicit `contentTintColor` for idle/error so template renders on macOS 26.
- `Resources/Info.plist` — version bump to 0.2.0.

### Sparkle auto-update wiring (added late in this session)

- Dep: `Sparkle` 2.6+ via SPM, embedded as `Vox.app/Contents/Frameworks/Sparkle.framework` by `scripts/build-app.sh`.
- Public EdDSA key in `Resources/Info.plist` under `SUPublicEDKey`; **private key lives in macOS Keychain** (account: `Sparkle Account`, service depends on Sparkle defaults). Re-extract via `security find-generic-password -ga ed25519` or use Sparkle's `generate_keys -p` on the same Mac. **Don't lose it** — without the matching private key, no future update can be signed and clients on this app will refuse it.
- Feed URL: `https://andykumeda.github.io/vox/appcast.xml` — backed by `docs/appcast.xml` on `main` branch (GitHub Pages serves from `/docs`).
- Signed update tool: `.build/artifacts/sparkle/Sparkle/bin/sign_update <Vox.dmg>` — outputs `sparkle:edSignature` and `length` for the appcast entry.
- Schedule: `SUEnableAutomaticChecks=true`, `SUScheduledCheckInterval=86400` (1/day). Manual via menu → "Check for Updates…".

#### Cutting a new release

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
2. `./scripts/make-dmg.sh` (which calls `build-app.sh`).
3. `.build/artifacts/sparkle/Sparkle/bin/sign_update dist/Vox.dmg` — copy the printed signature + length.
4. Add a new `<item>` entry at the top of `docs/appcast.xml`'s `<channel>` with the new version, pubDate, signature, length, and the GitHub release download URL.
5. `git commit && git push` (Pages re-deploys automatically).
6. `git tag vX.Y.Z && git push origin vX.Y.Z`.
7. `gh release create vX.Y.Z --title "Vox X.Y.Z" --notes "..." dist/Vox.dmg` — must use the **exact** filename `Vox.dmg` so the appcast URL matches.
8. Existing installs ≥ 0.2.1 will pick it up at next launch (or via "Check for Updates…").

### Open items / TBD

- **Prose-mode idle icon color** — currently `.systemBlue`. User wants to pick a different color later. One-line change in `MenuBarController.refreshIcon` (`tint:` for `.idle` when `forceProseMode == true`).
- **Mic returning rms=0 after sleep / first launch** — was actually mic muted at OS level. Not a code bug; documenting in case it recurs and looks like one. If silence-gate trips on every recording, check System Settings → Sound → Input.
- **Single-modifier hotkeys can collide with system shortcuts** — binding bare ⌘ or ⌥ as a record hotkey will fire on every Cmd/Opt-letter combo the user types (because flagsChanged fires when the modifier alone briefly matches before the letter arrives). Workable for press-and-hold use, awkward for tap-toggle. Not a bug, just a UX caveat.

### Session test plan that works

```
./scripts/build-app.sh
pkill -f 'Vox.app/Contents/MacOS/vox' || true
open dist/Vox.app
# Open Settings → record a Fn-only hotkey → save → confirm no crash
# Toggle mode via menu → icon changes (purple ⇄ blue bubble)
# Hold Fn → speak → release → text pastes
```

---

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
