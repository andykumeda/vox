# Handoff — Vox state as of 2026-04-29 (PM)

## Session 2026-04-29 PM — Meeting Transcription additive plan locked (implementation not started)

**Status:**
- Meeting transcription work is **planned but not yet implemented**.
- Primary constraint explicitly locked: **existing dictation STT quality/latency/reliability must not regress**.
- Engineer-ready execution plan created at `docs/superpowers/plans/2026-04-29-meeting-transcription-additive.md`.

**Locked product decisions (from stakeholder):**
1. Meeting capture source: **system/call audio only**.
2. Output UX: **in-app transcript list + export**.
3. Diarization in v1: **no**.
4. Consent UX: **one-time acknowledgment**.
5. Priority: transcript **accuracy/completeness** over summarization.
6. Storage default: **Application Support** (app-managed), export for sharing.

**Implementation sequence:**
- M1: additive scaffolding (settings, consent, system-audio preflight, menu actions)
- M2: chunked meeting pipeline + timestamped transcript persistence/list/export
- M3: hardening + strict dictation non-regression gates + telemetry/recovery

**Critical no-regression rule for future sessions:**
- Any PR that touches shared STT paths must run dictation regression checks and may not merge if baseline quality/latency/reliability drifts.

**Next action for next engineer session:**
1. Start M1 task checklist in plan doc and check off items as implemented.
2. Add/adjust tests in `Tests/voxTests/` before wiring meeting UI behavior.
3. Update this handoff with commit SHAs and remaining checklist items after each milestone increment.

---

## Session 2026-04-29 PM — 0.3.2 SHIPPED + uncommitted 0.3.3 transport-retry fix

**Status:**
- **0.3.2 is fully released.** GitHub Release `v0.3.2` exists with `Vox.dmg` (2,565,662 bytes), Sparkle EdDSA signature `WW4usR9mIl/xkNMz1P1MPZfKoMxl+bNKDTGx1IZXv/tnR08vR9zmFEKjHWdUJs0CrprNmZzKkUUGB/LIVORrDw==`, `docs/appcast.xml` updated (commit `d8e5488`), Pages CDN serving the new appcast.
- **Uncommitted local change** in `Sources/Vox/STT/OpenAITranscriber.swift` adds 30s request timeout (was 20s) and a single retry on transient URLError codes. Built locally and deployed to `~/Applications/Vox.app` for soak testing. Not yet committed, not yet versioned.

### Sparkle private key lives ONLY on AKsMini (Andy's Mac mini), NOT on the kumedaa Dev workstation — meaning kumedaa cannot sign releases

The keychain entry has label `Private key for signing Sparkle updates`, account `ed25519`, created 2026-04-28 on AKsMini's login keychain. Confirmed absent from kumedaa's keychain (this Dev workstation). The matching public key in `Resources/Info.plist` is `l/SNkU3yHLO0zYGfUf9+CPhK4n7+RO0G8DL/pq5EXGI=`.

**Implication:** every release must be built AND `sign_update`'d on AKsMini (or transfer the DMG bytes back). Today's 0.3.2 release was done split-machine: kumedaa pushed code, AKsMini built+signed+uploaded DMG, kumedaa pushed appcast.

**Recommended split for next release on AKsMini:**

```sh
# On AKsMini:
cd ~/Dev/vox
git pull
# Bump CFBundleShortVersionString + CFBundleVersion in Resources/Info.plist
rm -rf dist
./scripts/make-dmg.sh
.build/artifacts/sparkle/Sparkle/bin/sign_update dist/Vox.dmg
# (Keychain prompts once — click Always Allow)
gh release create vX.Y.Z dist/Vox.dmg --title "Vox X.Y.Z" --notes "..."
# Capture printed sparkle:edSignature + length
```

Then on EITHER Mac:

```sh
git pull
# Add new <item> at top of docs/appcast.xml using the captured signature + length
git add docs/appcast.xml
git commit --no-gpg-sign -m "release: appcast X.Y.Z"
git push
```

**Why DMG bytes differ across Macs:** `make-dmg.sh` runs `codesign` with whichever local identity matches `vox-dev` (cert SHA differs per machine — kumedaa: `117CAD808BCBB8E59356AEF16D3E9A17A3344705`, AKsMini: unknown), and timestamps embed in the bundle. So `Vox.dmg` produced on kumedaa was 2,565,879 bytes; on AKsMini, 2,565,662 bytes. The Sparkle signature is over the DMG bytes — the DMG you upload to GH Release MUST be the exact one `sign_update` saw. **Do not regenerate the DMG between sign_update and gh release create.**

### Why kumedaa was stuck

1. `sign_update dist/Vox.dmg` over SSH on AKsMini failed with `ERROR! The operating system has blocked access to the Keychain.` — Keychain ACL needs interactive Keychain Access app to grant the binary access, or just run from a local Terminal where the user can click Allow.
2. `security find-generic-password -a ed25519 -w` over SSH likewise blocked. Path B (export key to file, sign with `--ed-key-file`) was attempted; user ended up running `sign_update` directly from a local Terminal session on AKsMini and that worked.
3. After signing on AKsMini, kumedaa's local DMG had different bytes — invalidates signature. Resolution: AKsMini ran `gh release create v0.3.2 dist/Vox.dmg` itself.

### TCC pain encountered today (worth knowing for the future)

- Copying a kumedaa-signed `dist/Vox.app` over the AKsMini-signed `~/Applications/Vox.app` swaps cdhash → TCC drops Input Monitoring + Accessibility + Microphone grants for the new bundle. `tccutil reset Accessibility/ListenEvent/Microphone com.andykumeda.vox` clears stale state and lets Vox re-prompt cleanly.
- Multiple stale Vox instances after `pkill` is recurring: use `pkill -9` and verify with `pgrep -af 'Vox.app/Contents/MacOS/vox'` before relaunching.
- During release-day testing the user saw "transcription failed: Transport error: The request timed out." surfacing at ~3 seconds (not 20s). `curl` to `api.openai.com` from the same Mac was 84ms. Diagnosis: URLSession in the running app cached a dead nw_path after a brief network blip; fast-fail with `URLError.timedOut` localizes as "request timed out". Restart cleared it. Repro frequency was high enough that the user asked for code-level mitigation.

### Uncommitted 0.3.3 candidate fix

`Sources/Vox/STT/OpenAITranscriber.swift`:

- `request.timeoutInterval = 30.0` (was 20.0) — gives long dictations more headroom but still surfaces stalls quickly.
- Extracted send into `private static func sendWithRetry(_:)` — single retry (max 2 attempts total, 500ms backoff) on `.timedOut`, `.networkConnectionLost`, `.dnsLookupFailed`, `.notConnectedToInternet`, `.cannotConnectToHost`. Other `URLError` codes and non-URLError errors throw immediately (no retry on auth or HTTP errors).

Worst-case latency: 30s × 2 + 500ms = ~60.5s. That's generous but the alternative is still the silent-hang user reported. If the retry feels too slow in practice, drop to 15s timeout × 2 attempts.

Build verified on kumedaa (`swift build` clean, only pre-existing warnings). `swift test` could not run on kumedaa because XCTest module is missing (CommandLineTools only, no full Xcode). **Run `swift test` on AKsMini before committing** to confirm no regressions across the 209-test suite. Also smoke-test live: hold Fn → speak → release on a Wi-Fi flap if you can simulate one.

If retry+timeout proves out, ship as 0.3.3:

```sh
# On AKsMini:
cd ~/Dev/vox && git pull
swift test                 # confirm 209+ pass
# Bump CFBundleShortVersionString=0.3.3, CFBundleVersion=7 in Resources/Info.plist
git add Sources/Vox/STT/OpenAITranscriber.swift Resources/Info.plist
git commit --no-gpg-sign -m "release: 0.3.3 — STT request retry + 30s timeout"
git tag v0.3.3 && git push && git push origin v0.3.3
rm -rf dist && ./scripts/make-dmg.sh
.build/artifacts/sparkle/Sparkle/bin/sign_update dist/Vox.dmg
gh release create v0.3.3 dist/Vox.dmg --title "Vox 0.3.3" --notes "STT request retry + 30s timeout"
# Then on either Mac: prepend appcast item, commit+push
```

---

## Session 2026-04-29 AM — 0.3.2 release pending: transcribe timeout + slash dictation

**Context:** User on remote SSH session reported two production bugs in 0.3.1: (1) transcription hangs forever after recording; (2) cannot dictate "/" so Claude Code / Slack / Discord slash commands are unreachable. Code fixed and pushed; **release artifact (DMG + appcast + GitHub Release) still needs local Mac to finish** because Sparkle's `sign_update` reads its EdDSA private key from the macOS Keychain and the Keychain is locked over SSH.

### Status at handoff

**Pushed to GitHub (`main`):**
- Commit `e460c89` — code fixes + version bump to `0.3.2` (`CFBundleVersion=6`)
- Tag `v0.3.2` pushed
- 209/209 tests pass

**NOT pushed yet (needs local Mac):**
- `dist/Vox.dmg` — built and ad-hoc signed in this session at `dist/Vox.dmg` (2.4M), but Sparkle EdDSA signature missing → Sparkle clients will reject it. **Rebuild from scratch locally; don't trust the remote-built one.**
- `docs/appcast.xml` — still shows 0.3.1 as latest item. Sparkle on user's machine correctly reports "no update" because there is no 0.3.2 entry.
- GitHub Release `v0.3.2` — not created. `gh release list` shows latest as v0.3.1.

### What changed in code

**`Sources/Vox/STT/OpenAITranscriber.swift:46`** — added `request.timeoutInterval = 20.0`. URLSession default is 60s; without an explicit timeout, a stalled OpenAI call left `state = .transcribing` for 60s. Symptom: orange pulsing menu icon "never finishes" after recording. 20s gives long dictations room while surfacing failure fast.

**`Sources/Vox/Text/PostProcessor.swift`** — added spoken-slash handling in command mode. The 0.3.1 code intentionally skipped this (comment cited "cd slash usr slash local" ambiguity). Reversed the call:
- New entry in `spokenPunctReplacements` (line 230): `\bslash\b` → `/`
- Two-pass glue (lines 281-298):
  - Pass A: `/\s+(\w)` → `/$1` — kills space after slash. Covers leading "slash help" → "/help" AND first slash in a path.
  - Pass B: `(/\w+)\s+/` → `$1/` (looped 3×) — collapses subsequent slashes only when the previous token is `/word`. Preserves intentional "cat /tmp/file" because no spoken-slash signature.

**`Tests/voxTests/PostProcessorTests.swift`** — three new cases at end of command-mode block:
- `testCommandSlashWordGluesPath` — "cd slash usr slash local" → "cd /usr/local"
- `testCommandLeadingSlashWord` — "slash help" → "/help"
- `testCommandLeavesIntentionalPathSpaceAlone` — "cat /tmp/some-file.txt" untouched

### Local-finish steps (run on user's Mac, NOT over SSH)

```sh
cd /Users/andy/Dev/vox
git pull                                              # gets e460c89 + v0.3.2 tag

# Rebuild — don't trust dist/Vox.dmg from remote session
rm -rf dist
./scripts/make-dmg.sh                                 # builds + ad-hoc signs + creates DMG

# Sign with Sparkle EdDSA key (Keychain prompt expected once)
.build/artifacts/sparkle/Sparkle/bin/sign_update dist/Vox.dmg
# → outputs:  sparkle:edSignature="..." length=NNNNNNN
```

Add a new `<item>` block at the **top** of `docs/appcast.xml` (above the 0.3.1 item):

```xml
<item>
    <title>Vox 0.3.2</title>
    <pubDate>Wed, 29 Apr 2026 16:15:00 +0000</pubDate>
    <sparkle:version>6</sparkle:version>
    <sparkle:shortVersionString>0.3.2</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
    <description><![CDATA[
        <ul>
            <li><strong>Fix:</strong> Transcription no longer hangs indefinitely when OpenAI stalls. Added a 20s request timeout so failures surface and the menu icon resets.</li>
            <li><strong>Feature:</strong> Spoken "slash" now becomes "/" in command mode. "slash help" → "/help" for Claude Code / Slack / Discord slash commands. "cd slash usr slash local" → "cd /usr/local".</li>
        </ul>
    ]]></description>
    <enclosure
        url="https://github.com/andykumeda/vox/releases/download/v0.3.2/Vox.dmg"
        sparkle:edSignature="PASTE_FROM_SIGN_UPDATE"
        length="PASTE_FROM_SIGN_UPDATE"
        type="application/octet-stream" />
</item>
```

Finish:

```sh
git add docs/appcast.xml
git commit --no-gpg-sign -m "release: appcast 0.3.2"
git push

gh release create v0.3.2 dist/Vox.dmg \
    --title "Vox 0.3.2" \
    --notes "Transcription timeout + slash dictation"
```

GitHub Pages CDN cache: ~10 min after the appcast push. Sparkle then offers the update on **Check for Updates…** click. If not, `tail -f ~/Library/Logs/vox.log` while clicking — Sparkle errors land there.

### Troubleshooting hooks for the new session

**If transcribe still hangs after upgrade:** check `vox.log` for `transcription failed:` line. The 20s timeout will throw `TranscriptionError.transportError(...)` after exactly 20s. If hangs persist past 20s, the await is somewhere else — likely Smart Cleanup (5s) or `injector.paste`. Note Smart Cleanup timeout is in `CleanupLLMClient.swift:68` already at 5s.

**If "slash help" still shows as literal text:** mode detection — Claude Code is a terminal app, so `ContextDetector` should pick `.command` for it. Check `vox.log` for `mode=command` on the recorded line. If `mode=prose`, the slash glue won't fire — prose mode doesn't run `expandSpokenPunctuation`. Either toggle the menu mode override to `.command`, or extend slash handling into the prose pipeline (separate decision — current scope is command mode only).

**If Sparkle still says no update available after appcast push:**
1. `curl -s https://andykumeda.github.io/vox/appcast.xml | head -25` — confirm 0.3.2 is the first item.
2. GitHub Pages cache up to 10 min.
3. The `<enclosure url=...>` must point to the released DMG; `gh release create v0.3.2 dist/Vox.dmg` must have run before user clicks Check for Updates.

### Why the remote SSH session couldn't finish

Three keychain-gated steps:
1. `codesign --sign vox-dev` — fails with `errSecInternalComponent`. The vox-dev cert's private key ACL requires interactive Keychain unlock; SSH has no GUI to satisfy it. Workaround used here: ad-hoc sign (`codesign --sign -`). Local TCC perms reset after that, which is fine for release DMGs (UPDATING.md notes releases are ad-hoc anyway).
2. `sign_update dist/Vox.dmg` — Sparkle EdDSA private key in Keychain. Same block: `ERROR! The operating system has blocked access to the Keychain.` No ad-hoc workaround — Sparkle clients reject unsigned updates. **Must run from local Terminal.**
3. `gh release create` works fine over SSH (it's just an API call), but pointless without a Sparkle-signed DMG.

---

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
