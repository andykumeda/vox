# Handoff — Vox state as of 2026-05-26 (Release 0.7.23 auto relaunch)

**Status:** Release 0.7.23 is cut from `main`. Release commit `2819c76` is tagged `v0.7.23` and pushed. GitHub release: `https://github.com/andykumeda/vox/releases/tag/v0.7.23`. `Resources/Info.plist` bumped to `0.7.23` / build `42`. `dist/Vox.app` + `dist/Vox.dmg` rebuilt locally and signed with the persistent `vox-dev` identity. Sparkle EdDSA signature for the DMG: `T+p+WrzmPrwWRYEgL3nqvdHF3D9cHZSVqXDncStVwkEDuth+OfZPyNR7znn6lF3BVPIceaI3zKcZLvabcBwsAQ==`; length `2618015`. `docs/appcast.xml` has a new top item pointing at `https://github.com/andykumeda/vox/releases/download/v0.7.23/Vox.dmg`. User reported repeated failures from the same remote Mac/server, so local `~/Library/Logs/vox.log` is not expected to contain the failure details.

**Change:**
- `Sources/vox/App/AutoRelaunch.swift`: Vox now installs `~/Library/LaunchAgents/com.andykumeda.vox.plist` on normal app launch, then hands off to a launchd-managed instance using `--vox-launch-agent`. The LaunchAgent uses `KeepAlive` with `Crashed=true` and `SuccessfulExit=false`, so crashes / abnormal exits are restarted automatically while the normal **Quit Vox** path exits cleanly and stays quit.
- `Sources/vox/App/AppDelegate.swift`: startup calls the auto-relaunch installer after the relocation check and before initializing app services.
- `Tests/voxTests/AutoRelaunchTests.swift`: covers the generated LaunchAgent label, arguments, KeepAlive policy, session type, throttling, and launchd log paths.
- `README.md`, `Resources/help.md`: document the auto-relaunch agent and where it lives.
- `Resources/Info.plist`, `docs/appcast.xml`: 0.7.23 Sparkle metadata.

**Verification:**
- `swift test` passed: 333 tests, 0 failures.
- `./scripts/make-dmg.sh` succeeded and produced `dist/Vox.dmg`.
- `.build/artifacts/sparkle/Sparkle/bin/sign_update dist/Vox.dmg` produced the signature and length above.
- GitHub release asset `Vox.dmg` uploaded with size `2618015` and SHA-256 `6db3c90a1db8cb245dc4c05f9704db29f658d7d3a2861207ef5ca71ccfa422cc`.
- Public appcast at `https://andykumeda.github.io/vox/appcast.xml` advertises `Vox 0.7.23`, Sparkle version `42`, the matching EdDSA signature, and the GitHub DMG URL.

**Remaining caveats / next steps:**
- This has not been live-smoked on the remote Mac yet. After updating there through Sparkle, launch Vox once so the LaunchAgent is installed there. Then verify `~/Library/LaunchAgents/com.andykumeda.vox.plist` exists and that an abnormal termination relaunches Vox. Normal menu quit should not relaunch.

---

# Handoff — Vox state as of 2026-05-23 (Post-0.7.22 UI follow-ups)

## Session 2026-05-23 — Meeting panel selection + Settings fronting

**Status:** Local code/docs changes on top of `v0.7.22` / `main`. No version bump, no appcast edit, and no Sparkle release for these UI follow-ups yet. The remote Mac will not have this version until the next Sparkle release is cut and installed there.

**Changes:**
- `Sources/vox/App/MainWindow.swift`: selecting the **Meeting** section in the main Vox window now brings the floating Meeting HUD forward. Selecting **Settings** raises the Vox window to `.floating` level and orders it front regardless so it does not hide behind larger normal app windows; switching away from Settings resets the main window to normal level.
- `Sources/vox/App/MenuBarController.swift`: the menu-bar **Meeting** item routes through `MainWindowController.showMeeting()`, so it opens the Meeting view and surfaces the floating HUD through the same path as the sidebar.
- `Sources/vox/App/SettingsWindow.swift`: the legacy standalone settings controller also uses floating level plus `orderFrontRegardless()` when shown.
- `README.md`, `Resources/help.md`: updated Meeting and Settings behavior.

**Verification:**
- `swift test` passed: 330 tests, 0 failures.

**Remaining caveats / next steps:**
- These UI follow-ups have not been pushed out through Sparkle, so the remote Mac does not have them yet.
- User reported after this local commit that the Meeting window still is not opening. Do not assume `bbc3965` fixed the Meeting selection/menu path; review later when there is time to test. Start by confirming whether the intended surface is the main Vox Meeting section, the floating `MeetingHUDPanel`, or both, then trace `MenuBarController.openMeetingPanel()`, `MainWindowController.showMeeting()`, sidebar `onChange`, and the currently running app build/version.
- Next-session security/privacy task: review how dictation recordings, meeting audio, meeting transcripts, summaries, and dictation history are stored and protected. Define a plan so they cannot be viewed by other local users or unauthorized processes without permission. Check filesystem locations, file/directory permissions, retention behavior, transcript browser exposure, exports, backups/sync implications, and whether encryption, Keychain-protected keys, app-level locking, or explicit privacy documentation is needed.
- Next-session remote-control task: decide whether **Remote Control Mode** is still necessary. It currently forces the remote-control insertion path in `TextInjector`, but prior notes say it did not improve the observed remote paste issue. Live-test the current async remote paste behavior in both topologies (Vox running on the viewer Mac vs. Vox running on the remotely controlled Mac), then either keep and clarify the toggle, redesign it, or remove it from the menu/settings/docs.
- Related remote-session task: prevent both local and remote Vox instances from triggering on the same hotkey when connecting from another Mac. Today the viewer Mac and the remotely controlled Mac can both hear the hotkey and start recording. Explore a way to suppress or pause the remote Vox hotkey listener during remote-control sessions, such as a per-Mac "ignore remote hotkeys" mode, automatic remote-session detection, a mutually exclusive local/remote role setting, or a safer default hotkey profile for the remote Mac.
- Related remote-control punctuation task: when **Remote Control Mode** is on, RustDesk inserts `/` instead of `?`. VNC/Screen Sharing has not been tested for this specific case. Next session should test shifted punctuation through the remote-control insertion path and compare RustDesk vs. VNC before deciding whether Remote Control Mode needs a different paste/typing strategy.
- Manual UI verification is still useful after the next local app rebuild/relaunch: select Meeting from the sidebar/menu and confirm the HUD comes forward; open Settings behind another large window and confirm Vox raises above it.

---

# Handoff — Vox state as of 2026-05-23 (Release 0.7.22)

## Session 2026-05-23 — Release 0.7.22: async remote paste + recorder stop deadlock fix

**Status:** Release 0.7.22 is cut from `main`. Release commit `10a5ff9` is tagged `v0.7.22` and pushed. GitHub release: `https://github.com/andykumeda/vox/releases/tag/v0.7.22`. `Resources/Info.plist` bumped to `0.7.22` / build `41`. `dist/Vox.app` + `dist/Vox.dmg` rebuilt locally and signed with the persistent `vox-dev` identity. Sparkle EdDSA signature for the DMG: `+djJoZJmt/bYjTyfhovwkEXlfB+qVIdcJg4CiYt8D6w9vl1CkPYnBoz3wnDOK9hbnM9fo/XSB0cgFfak117hAA==`; length `2613254`. `docs/appcast.xml` has a new top item pointing at `https://github.com/andykumeda/vox/releases/download/v0.7.22/Vox.dmg`.

**Why 0.7.22 now:** The remote Mac does not have the post-0.7.21 fixes, and local Vox froze on Fn release while stopping an AVAudioEngine tap. This release packages the async remote paste finalization plus the recorder stop deadlock fix for Sparkle delivery.

**Code/docs included:**
- `Sources/vox/App/MenuBarController.swift`, `Sources/vox/Text/TextInjector.swift`, `Tests/voxTests/TextInjectorTests.swift`: async target-specific paste flow for fresh dictation and Paste Last Transcription, including remote clipboard waits that do not block the main actor.
- `Sources/vox/Audio/AudioRecorder.swift`: `stop()` releases `AudioRecorder.lock` before `removeTap(onBus:)`, avoiding the main-thread/audio-tap lock inversion observed in the frozen local app.
- `AGENTS.md`: repo-specific agent workflow, verification, documentation, remote paste, and release guardrails.
- `README.md`, `Resources/help.md`, `docs/remote-dictation-status.md`, `HANDOFF.md`: current remote paste behavior, deployment state, and release notes.
- `docs/appcast.xml`, `Resources/Info.plist`: 0.7.22 Sparkle metadata.

**Verification:**
- `swift test` passed: 330 tests, 0 failures.
- `./scripts/make-dmg.sh` succeeded and produced `dist/Vox.dmg`.
- `.build/artifacts/sparkle/Sparkle/bin/sign_update dist/Vox.dmg` produced the signature and length above.
- GitHub release asset `Vox.dmg` uploaded with size `2613254` and SHA-256 `99da552d98365e57bfcd1bddbaeab6e59e6ec27db1b39eb0a5d977540f988447`.
- Public appcast at `https://andykumeda.github.io/vox/appcast.xml` advertises `Vox 0.7.22`, Sparkle version `41`, the matching EdDSA signature, and the GitHub DMG URL.
- Local frozen Vox PID `63812` was terminated. Rebuilt `dist/Vox.app` was launched locally as PID `7445`, reporting version `0.7.22` / build `41`.

**Remaining caveats / next steps:**
- On the remote Mac, use Vox -> Check for Updates. Re-grant Mic / Input Monitoring / Accessibility if macOS prompts after the ad-hoc-signed update.
- Non-critical next programming session: improve prose number normalization for time context. Current `NumberNormalizer` intentionally keeps bare small numbers as words in prose, so phrases like "around four" can stay `four` even when the speaker means a time. Add context-aware tests/rules for time cues such as `at`, `around`, `by`, `before`, `after`, `until`, `o'clock`, `AM`, `PM`, `morning`, `afternoon`, `evening`, and `tonight`, while avoiding broad conversion of ordinary counts like "I have four ideas."
- Non-critical next programming session: decide how to handle spoken quote markers in prose. Vox does not currently have deterministic handling for phrases such as "quote unquote something", "quote something unquote", or "open quote something close quote"; if it works, it is coming from Whisper or Smart Cleanup rather than `PostProcessor`. Add tests before coding because "quote unquote" can mean literal quote marks around the next phrase, scare quotes around one word, or plain spoken filler depending on context.

---

# Handoff — Vox state as of 2026-05-23 (Audio recorder stop deadlock fix)

## Session 2026-05-23 — Fix frozen app on Fn release

**Status:** Code fix on top of `8398141` / `main`. No version bump, no Sparkle release, no appcast edit. This fix is not in the currently frozen running app and is not on the remote Mac.

**Cause found:** Running Vox PID `63812` (`dist/Vox.app`, version `0.7.21` build `40`, launched at 12:18 before the latest commit) froze after logging `Fn release` at 12:58:14 with no following `recording saved` line. A `sample` showed the main thread blocked in `AudioRecorder.stop()` at `engine.inputNode.removeTap(onBus: 0)`, while `RealtimeMessenger.mServiceQueue` was running the audio tap callback in `AudioRecorder.handle(buffer:)` and waiting for the same `AudioRecorder.lock`. `removeTap` waits for in-flight tap callbacks to drain, so holding the recorder lock while calling it deadlocked the main thread.

**Code change:**
- `Sources/vox/Audio/AudioRecorder.swift`: `stop()` now marks `isRecording = false`, releases `lock`, then removes the tap/stops the engine, and only reacquires `lock` to finalize the WAV header and clear recorder state. The converter is also cleared on successful stop.

**Verification:**
- `swift test` passed: 330 tests, 0 failures.

**Remaining caveats / next steps:**
- The frozen running app still needs to be terminated and relaunched from a rebuilt `dist/Vox.app`; source changes cannot unstick the already-deadlocked process.
- These post-0.7.21 fixes, including the remote paste finalization and this audio stop fix, have not been pushed through Sparkle. The remote Mac will not have them until a new Sparkle release is cut and installed there.

---

# Handoff — Vox state as of 2026-05-23 (Post-0.7.21 remote paste finalization)

## Session 2026-05-23 — Remote paste async finalization + agent instructions

**Status:** Code-only finalization on top of `v0.7.21` / `main`. No version bump, no Sparkle release, no appcast edit. These recent fixes have **not** been pushed out through Sparkle, so the remote Mac will not have this version until a new release is cut and installed there. User reported testing has been completed.

**Code changes:**
- `Sources/vox/App/MenuBarController.swift`: fresh dictation and Paste Last Transcription now call `TextInjector.pasteAsync`, so remote sync waits do not block the main actor/menu flow. Suffix keys are scheduled after the awaited paste attempt completes.
- `Sources/vox/Text/TextInjector.swift`: paste is split into prepare/perform/restore steps with sync and async execution paths. Remote waits use `Task.sleep` in the async path.
- `Sources/vox/Text/TextInjector.swift`: Screen Sharing/VNC still tries exact System Events text keystrokes first, then shared-clipboard remote `Cmd+V`, then menu paste / physical typing fallbacks. RustDesk uses delayed exact clipboard paste plus remote `Cmd+V`, with Caps Lock-aware physical typing as fallback.
- `Sources/vox/Text/TextInjector.swift`: System Events text chunks normalize `\r` and `\r\n` to newline key events.
- `Tests/voxTests/TextInjectorTests.swift`: updated target capability expectations and added carriage-return normalization coverage.
- `AGENTS.md`: populated the previously empty auto-created placeholder with repo-specific agent workflow, verification, documentation, remote paste, and release guardrails.

**Docs updated:**
- `README.md` and `Resources/help.md`: updated remote desktop paste behavior for Screen Sharing/VNC, RustDesk, Remote Control Mode, and Paste Last.
- `docs/remote-dictation-status.md`: marked the current remote paste state as finalized/tested, documented the async follow-up, and replaced stale "still broken" language with regression watch points.
- `HANDOFF.md`: this entry.

**Verification:**
- `git diff --check` passed.
- `swift test` passed: 330 tests, 0 failures.
- Manual/live testing was already completed by the user before finalization.

**Remaining caveats / next steps:**
- No active remote-dictation blocker is recorded in this checkout.
- The remote Mac does not have these post-0.7.21 fixes yet. To deploy them there, cut a new Sparkle release from this commit and update via Vox -> Check for Updates.

---

# Handoff — Vox state as of 2026-05-22 (Release 0.7.8)

## Session 2026-05-22 — Release 0.7.8: VNC shared clipboard exact paste, RustDesk best-effort

**Status:** Release 0.7.8 is cut from `main`. Release commit `f56cb63` is tagged `v0.7.8` and pushed. `Resources/Info.plist` bumped to `0.7.8` / build `27`. `dist/Vox.app` + `dist/Vox.dmg` rebuilt locally and signed with the persistent `vox-dev` self-signed identity. Sparkle EdDSA signature for the DMG: `exGk/mcmXMlTeqREXY8IzwuAIGOsnvmq+RQwJFAESzem8yYsUTSvL0C+PTy/Y4Y6Rei+wEQe+gFCCbm+0QdQAQ==`; length `2592433`. `docs/appcast.xml` has a new top item pointing at `https://github.com/andykumeda/vox/releases/download/v0.7.8/Vox.dmg`.

**Why 0.7.8 now:** User live-tested the remote insertion paths and chose one high-fidelity target over two partial targets. RustDesk can insert text and now appears to capitalize sentence starts, but it still does not reliably produce shifted punctuation such as a final question mark. VNC/Screen Sharing is the preferred exact path.

**Code changes:**
- `Sources/vox/Text/TextInjector.swift`: Screen Sharing/VNC no longer uses physical typing. Vox writes the transcript to the local clipboard, ensures Screen Sharing's `Edit > Use Shared Clipboard` is enabled, waits 1.0 s for synchronization, then sends a remote `Cmd+V` key-code paste.
- `Sources/vox/Text/TextInjector.swift`: Screen Sharing/VNC is treated as requiring exact paste; if shared clipboard or remote paste is unavailable, Vox logs the failure instead of degrading into partial physical typing.
- `Sources/vox/Text/TextInjector.swift`: RustDesk remains on unmodified physical typing because live testing showed RustDesk menu paste inserted nothing and synthetic modifiers are unreliable. RustDesk may still approximate shifted punctuation, including `?` to `.`, but it is left on the path that actually delivers text.
- `Tests/voxTests/TextInjectorTests.swift`: updated target-selection behavior, exact-paste flags, pre-paste delay, and physical punctuation approximation coverage.

**Docs updated:**
- `README.md` and `Resources/help.md`: document Screen Sharing/VNC as the high-fidelity shared-clipboard paste path and RustDesk as best-effort physical typing.
- `docs/appcast.xml`: prepended 0.7.8 release notes.

**Verification:**
- `swift test` passed: 313 tests, 0 failures.
- `./scripts/make-dmg.sh` succeeded and produced `dist/Vox.dmg`.
- `.build/artifacts/sparkle/Sparkle/bin/sign_update dist/Vox.dmg` produced the signature and length above.
- User live test before release: VNC is working the way it should; RustDesk capitalizes the first letter but still misses final question marks.

**Release actions completed:**
- Pushed release commit `f56cb63` to `main`.
- Pushed tag `v0.7.8`.
- Created GitHub release `v0.7.8` with `dist/Vox.dmg` attached.
- Verified the public appcast advertises `Vox 0.7.8`, Sparkle version `27`, and the matching EdDSA signature.
- Verified the GitHub DMG URL returns a download redirect and the release asset reports size `2592433`.
- `.claude/` and untracked `AGENTS.md` should remain untouched.

**Other-Mac update path:** on the remote Mac, use Vox → `Check for Updates…`. Re-grant Mic / Input Monitoring / Accessibility if macOS prompts after the ad-hoc-signed update. Use Screen Sharing/VNC when exact punctuation matters; keep RustDesk as the best-effort fallback.

---

# Handoff — Vox state as of 2026-05-22 (Release 0.7.7)

## Session 2026-05-22 — Release 0.7.7: Remote capitalization via Caps Lock physical typing

**Status:** Release 0.7.7 is being cut from `main`. `Resources/Info.plist` bumped to `0.7.7` / build `26`. `dist/Vox.app` + `dist/Vox.dmg` rebuilt and signed with the persistent `vox-dev` self-signed identity. Sparkle EdDSA signature for the DMG: `WIVYVj6SwHGcjOkom1ZkvfLptsEnL1E2jHYNh1BxbQWDoVA3p5aAbLnl5iurs6UApnVYq4UWjKtFDgm8SBOyCg==`; length `2590184`. `docs/appcast.xml` has a new top item pointing at `https://github.com/andykumeda/vox/releases/download/v0.7.7/Vox.dmg`.

**Why 0.7.7 now:** User reported that 0.7.6 did not fix remote insertion: RustDesk still lowercased sentence starts, and VNC produced repeated lowercase `a`s. That means RustDesk still drops synthetic Shift, while VNC ignores the Unicode payload and treats virtual keycode `0` as `a`.

**Code changes:**
- `Sources/vox/Text/TextInjector.swift`: Screen Sharing/VNC and RustDesk now both use a Caps Lock based physical typing fallback. Vox toggles Caps Lock around uppercase letter runs and types unmodified letter keycodes, avoiding synthetic Shift and VNC Unicode key payloads.
- `Sources/vox/Text/TextInjector.swift`: remote typing reads the initial Caps Lock state and restores it after insertion, including if Caps Lock was already active.
- `Tests/voxTests/TextInjectorTests.swift`: updated remote fallback coverage and added Caps Lock sequencing tests, including initially-active Caps Lock.

**Docs updated:**
- `README.md` and `Resources/help.md`: document Caps Lock based remote insertion for Screen Sharing/VNC and RustDesk.
- `docs/appcast.xml`: prepended 0.7.7 release notes.

**Verification:**
- `swift test` passed: 307 tests, 0 failures.
- `./scripts/make-dmg.sh` succeeded and produced `dist/Vox.dmg`.
- `.build/artifacts/sparkle/Sparkle/bin/sign_update dist/Vox.dmg` produced the signature and length above.

**Release actions completed:**
- Pending: commit, tag `v0.7.7`, GitHub release, public appcast verification.
- `.claude/` and untracked `AGENTS.md` were intentionally left untouched.

**Other-Mac update path:** on the remote Mac, use Vox → `Check for Updates…`; re-grant Mic / Input Monitoring / Accessibility if macOS prompts after the ad-hoc-signed update. This release should fix sentence-start capitalization in RustDesk and avoid the VNC lowercase-`a` failure from the Unicode path.

---

# Handoff — Vox state as of 2026-05-22 (Release 0.7.6)

## Session 2026-05-22 — Release 0.7.6: VNC Unicode text insertion preserves capitalization

**Status:** Release 0.7.6 is cut from `main`. `Resources/Info.plist` bumped to `0.7.6` / build `25`. `dist/Vox.app` + `dist/Vox.dmg` rebuilt and signed with the persistent `vox-dev` self-signed identity. Sparkle EdDSA signature for the DMG: `nWIRD4eFc7dJUyoG8ObIBZf/sxOWR6qda+H44bJPEbacu6BIKNCl5zEjnLeSe5i5mUKcbvA1CHDT+4LmrgkpDg==`; length `2589195`. `docs/appcast.xml` has a new top item pointing at `https://github.com/andykumeda/vox/releases/download/v0.7.6/Vox.dmg`.

**Why 0.7.6 now:** User reported that VNC insertion worked after 0.7.5 but sentence starts were lowercased. The prose post-processor still capitalizes sentence starts; this points to the Screen Sharing/VNC physical-key fallback losing synthetic Shift modifiers during remote forwarding.

**Code changes:**
- `Sources/vox/Text/TextInjector.swift`: Screen Sharing/VNC now sends Unicode text key events via `CGEvent.keyboardSetUnicodeString`, avoiding Shift-modified physical key events for text insertion.
- `Sources/vox/Text/TextInjector.swift`: RustDesk stays on the unmodified physical typing path because it is known to drop modifier keys.
- `Tests/voxTests/TextInjectorTests.swift`: added coverage that VNC/Screen Sharing uses the Unicode fallback while RustDesk uses physical typing.

**Docs updated:**
- `README.md` and `Resources/help.md`: document that Screen Sharing/VNC uses Unicode text events to preserve capitalization.
- `docs/appcast.xml`: prepended 0.7.6 release notes.

**Verification:**
- `swift test` passed: 306 tests, 0 failures.
- `./scripts/make-dmg.sh` succeeded and produced `dist/Vox.dmg`.
- `.build/artifacts/sparkle/Sparkle/bin/sign_update dist/Vox.dmg` produced the signature and length above.

**Release actions completed:**
- Tag `v0.7.6` pushed to GitHub.
- GitHub release `v0.7.6` created with `dist/Vox.dmg` attached.
- `.claude/` and untracked `AGENTS.md` were intentionally left untouched.

**Other-Mac update path:** on the remote Mac, use Vox → `Check for Updates…`; re-grant Mic / Input Monitoring / Accessibility if macOS prompts after the ad-hoc-signed update. If uppercase still fails, then the VNC client is ignoring Unicode key events too, and the next fallback should be a remote-side paste helper or a VNC-specific clipboard-send API rather than local key synthesis.

---

# Handoff — Vox state as of 2026-05-22 (Release 0.7.5)

## Session 2026-05-22 — Release 0.7.5: VNC bypasses clipboard paste and types directly

**Status:** Release 0.7.5 is cut from `main`. `Resources/Info.plist` bumped to `0.7.5` / build `24`. `dist/Vox.app` + `dist/Vox.dmg` rebuilt and signed with the persistent `vox-dev` self-signed identity. Sparkle EdDSA signature for the DMG: `LF0KejFOKJdQc5TXbVDrqmaJFglG6ViMZz2bpnA5sL88g+97p+OMZB1rBmkR7LGcvRTD22jq7zRlMfbmeGsaDg==`; length `2588241`. `docs/appcast.xml` has a new top item pointing at `https://github.com/andykumeda/vox/releases/download/v0.7.5/Vox.dmg`.

**Why 0.7.5 now:** User is operating from the remote Mac and needs the fix through Sparkle. 0.7.4 still did not insert into VNC: local clipboard held the transcript correctly, but the VNC client did not forward the paste action into the remote session. The fix now bypasses VNC clipboard paste entirely for Screen Sharing/VNC.

**Code changes:**
- `Sources/vox/Text/TextInjector.swift`: Screen Sharing/VNC now types the transcript directly with HID physical key events instead of using clipboard paste. It supports shifted characters for uppercase and common punctuation where VNC accepts modifier events.
- `Sources/vox/Text/TextInjector.swift`: RustDesk remains on the unmodified physical typing path because that client drops synthetic modifier keys.
- `Tests/voxTests/TextInjectorTests.swift`: added coverage for remote physical typing target selection, shifted Screen Sharing/VNC keystrokes, and RustDesk's unmodified fallback behavior.

**Docs updated:**
- `README.md` and `Resources/help.md`: document that Screen Sharing/VNC bypasses clipboard paste and types directly.
- `docs/appcast.xml`: prepended 0.7.5 release notes.

**Verification:**
- `swift test` passed: 305 tests, 0 failures.
- `./scripts/make-dmg.sh` succeeded and produced `dist/Vox.dmg`.
- `.build/artifacts/sparkle/Sparkle/bin/sign_update dist/Vox.dmg` produced the signature and length above.

**Release actions completed:**
- Tag `v0.7.5` pushed to GitHub.
- GitHub release `v0.7.5` created with `dist/Vox.dmg` attached.
- `.claude/` and untracked `AGENTS.md` were intentionally left untouched.

**Other-Mac update path:** on the remote Mac, use Vox → `Check for Updates…`; re-grant Mic / Input Monitoring / Accessibility if macOS prompts after the ad-hoc-signed update. VNC insertion should now behave like typed keys instead of clipboard paste.

---

# Handoff — Vox state as of 2026-05-22 (Release 0.7.4)

## Session 2026-05-22 — Release 0.7.4: VNC paste waits for clipboard sync and uses local Edit Paste

**Status:** Release 0.7.4 is cut from `main`. `Resources/Info.plist` bumped to `0.7.4` / build `23`. `dist/Vox.app` + `dist/Vox.dmg` rebuilt and signed with the persistent `vox-dev` self-signed identity. Sparkle EdDSA signature for the DMG: `JHiCtEAVAMq0ZcFZW9/oivmIbye9pUh/zIdIZnyqjZek/cMBfQCLkupIpRZW7bpV8uOk8OQcBmBeiSMz/sElAQ==`; length `2586930`. `docs/appcast.xml` has a new top item pointing at `https://github.com/andykumeda/vox/releases/download/v0.7.4/Vox.dmg`.

**Why 0.7.4 now:** User confirmed 0.7.3 still pasted the previous clipboard in VNC. Skipping clipboard restore prevented one race, but Vox still sent Paste immediately after setting the local pasteboard; the remote host could receive the paste command before the VNC client had synchronized the new transcript to the remote clipboard.

**Code changes:**
- `Sources/vox/Text/TextInjector.swift`: Screen Sharing/VNC now waits 1.5 s after writing the local pasteboard, then invokes the frontmost app's local Edit → Paste menu. If that AppleScript path fails, it falls back to the existing System Events `Cmd+V` path.
- `Sources/vox/Text/TextInjector.swift`: paste now logs detected frontmost bundle/name and selected paste target for future VNC/RustDesk diagnostics.
- `Tests/voxTests/TextInjectorTests.swift`: added coverage that Screen Sharing/VNC has a propagation delay while standard apps and RustDesk do not.

**Docs updated:**
- `README.md` and `Resources/help.md`: document the VNC clipboard-sync wait and local Edit → Paste path.
- `docs/appcast.xml`: prepended 0.7.4 release notes.

**Verification:**
- `swift test` passed: 304 tests, 0 failures.
- `./scripts/make-dmg.sh` succeeded and produced `dist/Vox.dmg`.
- `.build/artifacts/sparkle/Sparkle/bin/sign_update dist/Vox.dmg` produced the signature and length above.

**Release actions completed:**
- Tag `v0.7.4` pushed to GitHub.
- GitHub release `v0.7.4` created with `dist/Vox.dmg` attached.
- `.claude/` and untracked `AGENTS.md` were intentionally left untouched.

**Other-Mac update path:** on the other Mac, use Vox → `Check for Updates…`; re-grant Mic / Input Monitoring / Accessibility if macOS prompts after the ad-hoc-signed update. If VNC still pastes stale text, check `~/Library/Logs/vox.log` for the `paste target:` and `paste remote fallback:` lines to confirm whether the VNC client is being classified as `.screenSharing`.

---

# Handoff — Vox state as of 2026-05-22 (Release 0.7.3)

## Session 2026-05-22 — Release 0.7.3: cleanup profile, dictionary protection, and VNC clipboard fix

**Status:** Release 0.7.3 is cut from `main`. `Resources/Info.plist` bumped to `0.7.3` / build `22`. `dist/Vox.app` + `dist/Vox.dmg` rebuilt and signed with the persistent `vox-dev` self-signed identity. Sparkle EdDSA signature for the DMG: `/R3ZZ0MNX4iq+dhHrwHpXGmZVprSoNMm5havXviIZnhpWyjY5epeYvJsztUbzlHT9lqXUNH9N8yd600I7G4pCg==`; length `2584157`. `docs/appcast.xml` has a new top item pointing at `https://github.com/andykumeda/vox/releases/download/v0.7.3/Vox.dmg`. The other Mac can pick this up via Sparkle (`Check for Updates…`) once GitHub Pages serves the updated appcast and the GitHub release asset is available.

**Why 0.7.3 now:** Smart cleanup was over-polishing prose and could rewrite dictionary-protected names back to common spellings after the first dictionary pass. User also reported that VNC pasted the previous manual clipboard rather than the new voice transcript, which traced to restoring the local clipboard before the remote pasteboard had consumed it.

**Code changes:**
- `Sources/vox/Util/CleanupProfileStore.swift`: new store backed by `~/Library/Application Support/Vox/cleanup-profile.md`; empty file means default cleanup behavior.
- `Sources/vox/App/SettingsWindow.swift`: Smart cleanup settings now include a multiline personal instructions editor with Save, Reset, and Reveal File controls.
- `Sources/vox/Text/CleanupLLMClient.swift`: cleanup prompt now includes the personal profile when non-empty, active prose/both dictionary mappings, and stronger conservative wording to preserve voice and wording.
- `Sources/vox/App/MenuBarController.swift`: dictation still runs STT → `PostProcessor` → `CleanupProcessor`, then reapplies prose dictionary corrections after cleanup before history/paste.
- `Sources/vox/Text/CleanupDictionaryProtection.swift`: deterministic final dictionary pass for Smart cleanup output while leaving newline-bearing command-like output alone.
- `Sources/vox/Util/DictionaryMatcher.swift`: dictionary replacement now handles possessives such as `Leonard's` → `Lenard's`.
- `Sources/vox/Text/TextInjector.swift`: Screen Sharing/VNC paste targets skip the old-clipboard restore even when the user disables "keep transcription on clipboard after paste", avoiding remote pasteboard lag reading stale clipboard contents.

**Docs updated:**
- `README.md` and `Resources/help.md`: document the Smart cleanup profile file and the VNC clipboard behavior.
- `docs/appcast.xml`: prepended 0.7.3 release notes.

**Verification:**
- `swift test` passed: 302 tests, 0 failures.
- `./scripts/make-dmg.sh` succeeded and produced `dist/Vox.dmg`.
- `.build/artifacts/sparkle/Sparkle/bin/sign_update dist/Vox.dmg` produced the signature and length above.

**Release actions completed:**
- Tag `v0.7.3` pushed to GitHub.
- GitHub release `v0.7.3` created with `dist/Vox.dmg` attached.
- `.claude/` and untracked `AGENTS.md` were intentionally left untouched.

**Other-Mac update path:** on the other Mac, use Vox → `Check for Updates…`; re-grant Mic / Input Monitoring / Accessibility if macOS prompts after the ad-hoc-signed update. If Sparkle does not see 0.7.3 immediately, wait for GitHub Pages to finish publishing `docs/appcast.xml` from `main` and try again.

---

# Handoff — Vox state as of 2026-05-21 (Afternoon)

## Session 2026-05-21 — Release 0.7.2: remote desktop paste fallbacks for Screen Sharing/VNC and RustDesk

**Status:** Release 0.7.2 shipped. Release commit `8e80e06` is tagged `v0.7.2` and pushed to GitHub; GitHub release URL is `https://github.com/andykumeda/vox/releases/tag/v0.7.2`. `Resources/Info.plist` bumped to `0.7.2` / build `21`. `dist/Vox.app` + `dist/Vox.dmg` rebuilt and signed with the persistent `vox-dev` self-signed identity. Sparkle EdDSA signature for the DMG: `7DzQQsAC7ePwRC5HQe0im6XA4fJlb1y8n0UPDgMsRUMN4hDyxAusf8DQ5dbT4HX+TlJiTVpJhV0xVTHwf4r5Bw==`; length `2572621`. `docs/appcast.xml` has a new top item pointing at `https://github.com/andykumeda/vox/releases/download/v0.7.2/Vox.dmg`. The other Mac can pick this up via Sparkle (`Check for Updates…`) once GitHub Pages serves the updated appcast.

**Why 0.7.2 now:** dictation into a remote Mac through VNC/RustDesk was not receiving the transcript. The original paste path put text on the local pasteboard and synthesized `Cmd+V`; remote access apps were forwarding the `V` key but dropping the synthetic Command modifier, causing only a lowercase `v`, or no visible input. User confirmed the Screen Sharing/VNC fallback works. RustDesk needed a separate path because both System Events `Cmd+V` and `Edit > Paste` failed there.

**Code changes:**
- `Sources/vox/Text/TextInjector.swift`: frontmost app detection now selects a paste target: standard apps still use the existing synthesized `Cmd+V`; `com.apple.ScreenSharing` uses System Events `key code 9 using command down`; `com.carriez.rustdesk` bypasses paste entirely and types the transcript as unmodified physical keycodes through the HID event tap.
- RustDesk fallback intentionally trades fidelity for delivery. Because RustDesk drops synthetic Shift/Command modifiers, the fallback can lowercase letters and approximate shifted punctuation (`?`/`!` -> `.`, `:` -> `;`, quotes -> apostrophe, etc.). This is only used when RustDesk is the frontmost app.
- Paste Last Transcription uses the same `TextInjector.paste` path, so it benefits from the same remote fallbacks.

**Docs updated:**
- `README.md`: documents the Screen Sharing/VNC and RustDesk behavior, fixes the stale clipboard-default text (0.7.1 made "keep transcript on clipboard" the default), and updates the test count to 281.
- `Resources/help.md`: adds remote desktop paste troubleshooting and updates the meeting-provider wording so it no longer says meetings always transcribe through OpenAI.
- `docs/appcast.xml`: prepended 0.7.2 release notes.

**Verification:**
- `swift test` passed: 281 tests, 0 failures.
- `./scripts/make-dmg.sh` succeeded and produced `dist/Vox.dmg`.
- `.build/artifacts/sparkle/Sparkle/bin/sign_update dist/Vox.dmg` produced the signature and length above.
- Local app log during RustDesk test showed `paste remote fallback: RustDesk physical typing 26 chars`. Hands-on opposite-direction UI testing is still pending; user asked not to take over the screen-sharing UI while they were working.

**Release actions completed:**
- Commit `8e80e06` (`release: 0.7.2 remote paste fallbacks`) includes `Sources/vox/Text/TextInjector.swift`, `Resources/Info.plist`, `README.md`, `Resources/help.md`, `docs/appcast.xml`, and this handoff section as originally written.
- Tag `v0.7.2` pushed to GitHub.
- GitHub release `v0.7.2` created with `dist/Vox.dmg` attached.
- `.claude/` and untracked `AGENTS.md` were intentionally left untouched.

**Other-Mac update path:** on the other Mac, use Vox → `Check for Updates…`; re-grant Mic / Input Monitoring / Accessibility if macOS prompts after the ad-hoc-signed update. If Sparkle does not see 0.7.2 immediately, wait for GitHub Pages to finish publishing `docs/appcast.xml` from `main` and try again.

**Open follow-ups carried forward:** confirm RustDesk in the opposite direction after the other Mac updates; if uppercase/punctuation fidelity matters, the next likely path is a RustDesk-specific text-injection mechanism outside synthetic keyboard modifiers. Existing meeting follow-ups still stand: long-meeting (>2 GB) Deepgram fallback and persisted stream shifts for re-transcribe.

---

# Handoff — Vox state as of 2026-05-18 (Afternoon)

## Session 2026-05-18 — Release 0.7.1: VoIP-app audio capture + per-source diarization, dictation clipboard default, plus the May 11 + May 16 polish batch

**Status:** Release 0.7.1 cut from `main`. `Resources/Info.plist` bumped to `0.7.1` / build `20`. `dist/Vox.app` + `dist/Vox.dmg` (2,560,836 bytes) rebuilt and signed with the persistent `vox-dev` self-signed identity. Sparkle EdDSA signature `C66vl3pbsB2scriTVD+8i4BdUyoei1UVA+Jxr14y5W47TsAPj3HPhtFrlO7UjntDEZKeLNDvORRu8bPASVOGAQ==` generated for the DMG. `docs/appcast.xml` prepended with the 0.7.1 item pointing at `https://github.com/andykumeda/vox/releases/download/v0.7.1/Vox.dmg`. Second Mac picks up via Sparkle on next check (or "Check for Updates…" in Settings) — TCC re-prompts for Mic / Input Monitoring / Accessibility per the usual ad-hoc-signed cadence.

**Why 0.7.1 now:** second Mac is still on a pre-0.7 build with no audio retention, so the May 13 diagnostic showed `canReTranscribe` returning false silently because the gate requires both a terminal status AND `MeetingTranscriptStore().audioFile(id:)` existing on disk. Updating second Mac was the requested fix; rather than ship a stale 0.7.0 there while this Mac sits on three unreleased commits past the tag, we bundled the May 11 polish, the May 14 dictation clipboard flip, and the May 16 VoIP capture feature into a single 0.7.1.

**Commits rolled up into 0.7.1** (vs `v0.7.0` tag at `6317a91`):
- `adc21a5` `feat(meeting): capture VoIP-app audio + per-source diarization`
- `0edca38` `fix(dictation): keep transcript on clipboard by default`
- `ea565f1` `fix(meeting): HUD timer freezes on stop; auto-show pops during background transcribe`

**`adc21a5` — VoIP capture + per-source diarization:** SCStream cannot see audio from Phone.app / FaceTime — Continuity calls route through privileged CoreAudio paths that bypass the display tap. Added `MeetingProcessTap` (macOS 14.4+) that resolves PIDs for the UI apps plus the system daemons that actually render call audio (`callservicesd`, `avconferenced`, `imagent`, `identityservicesd`), builds a `CATapDescription` mixdown of those processes, wraps it in a private aggregate device, and writes AAC m4a alongside the existing mic + system streams. Deepgram pipeline switched from one-mixed-file to per-source: each input file (mic / phone / system) is its own request and segments are tagged by file boundary. Cross-stream diarization on a single mixed file had been collapsing distinct voices to one Speaker ID — per-source tags guarantee You-vs-other distinction while preserving within-source diarization for multi-caller scenarios. Speaker IDs are offset per source (0 system / +100 phone / nil for mic) to avoid collisions. Green reserved for "You" so the local label never matches any color from the remote speaker palette.

**`0edca38` — dictation clipboard default flipped to keep transcript:** restoring the prior clipboard ~1.5s after ⌘V races web text inputs (Comet, Perplexity sidebar, Slack web) that read the pasteboard asynchronously after the paste event — the restore landed first and the app pulled the previous clipboard contents instead of the transcript. Default flipped to `true` (keep transcript on clipboard); opt out in Settings if the prior behavior is preferred.

**`ea565f1` — HUD timer freeze, auto-show during background transcribe, Deepgram cost surface, sticky transcripts + Settings windows:** see the May 11 session block below for the full rationale and per-file diff — that work landed locally on May 11 and ships now as part of 0.7.1.

**Release artifacts to push:**
- `git commit` covers `Resources/Info.plist`, `docs/appcast.xml`, `HANDOFF.md`.
- `git tag v0.7.1` (`--no-gpg-sign`, per durable repo preference).
- `git push origin main && git push origin v0.7.1`.
- `gh release create v0.7.1 --title 'Vox 0.7.1' --notes-file -` (notes mirror the appcast bullets) and attach `dist/Vox.dmg`.

**Open follow-ups carried forward** (unchanged): long-meeting (>2 GB) Deepgram fallback; persisting `MeetingAudioMixer` shifts so re-transcribe uses real wall-clock offsets instead of `shift=0`; second-Mac TCC re-prompt UX after every ad-hoc install (still the same friction — Mic / Input Monitoring / Accessibility re-grant after the 0.7.1 update lands).

## Session 2026-05-11 — Post-0.7.0 polish: HUD timer freeze, auto-show during background transcribe, Deepgram cost surface, sticky transcripts + Settings windows

**Status:** Code-only patch on top of 0.7.0. No version bump, no release; dev workstation `dist/Vox.app` rebuilt. Push lands on `main`.

**User-reported issues fixed:**
1. **Meeting control panel did not pop when Teams meeting started while a previous meeting was still transcribing in the background.** Log confirmed `MeetingDetector: started — owner="Microsoft Teams"` fired correctly, but the auto-show callback bailed because `MeetingTranscriptionSession.shared.isActive` was still `true` during `.chunking` / `.transcribing`.
2. **HUD elapsed timer kept counting up after the user clicked Stop.** Root: `elapsed()` used `isActive ? now : session.endedAt`, and `isActive` covers `.chunking` / `.transcribing` — even though `stop()` had already set `endedAt`, the formula picked `now` and kept ticking through the transcribe phase.
3. **No surfaced rate for Deepgram on the meeting provider picker** (parallel to the per-minute rate shown for the dictation `TranscriptionModel` picker).
4. **Meeting transcripts window + Settings window did not follow the user across Spaces / full-screen apps**, unlike the floating meeting HUD which already had `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`.

**Code changes:**
- `Sources/vox/App/MeetingHUDPanel.swift` (`elapsed`): `referenceEnd = session?.endedAt ?? (isActive ? now : nil)`. Freezes the timer as soon as `stop()` sets `endedAt`; status badge still progresses through `Chunking…` / `Transcribing N/M` so the user can see what's happening.
- `Sources/vox/App/MenuBarController.swift` (detector `onMeetingStarted`): gate switched from `!isActive` to `!isRecording`. Panel auto-shows for a new meeting even while the previous one is still chunking/transcribing in the background. Record button stays disabled (the session's own `start()` would throw `.alreadyActive`) — panel is informational until the previous run lands.
- `Sources/vox/Util/AppSettings.swift`: `MeetingProvider.usdPerHour` — `.deepgram` = `0.258` (Nova-3 PAYG `$0.0043/min` with diarization included), `.openai` = `0.36` (`whisper-1` `$0.006/min`).
- `Sources/vox/App/SettingsWindow.swift` (provider section, inside the `if meetingMode` block): caption under the provider picker — `≈ $X.XX / hour of audio (mic + system audio billed separately, so ~2× meeting length)`. The 2× note is real: meetings record both streams independently, so a 1-hour meeting bills ~2 hours of audio against the provider.
- `Sources/vox/App/MeetingTranscriptsWindow.swift`, `Sources/vox/App/MainWindow.swift`, `Sources/vox/App/SettingsWindow.swift` (legacy `SettingsWindowController`): all three NSWindows now set `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`. `.stationary` is omitted on purpose — these are regular windows, not the floating HUD, so they should move with Spaces like normal app windows but still appear on every desktop.

**Why no `.stationary` here:** the meeting HUD is a borderless `NSPanel` floating at `.statusBar` level — `.stationary` keeps it pinned to screen coordinates as the user moves between Spaces. The transcripts + Settings + main windows are conventional titled windows. We want them visible across Spaces but not glued to a fixed screen position.

**Defaults left untouched:** `AppSettings.autoShowMeetingPanel` is still default OFF. User has it ON on this Mac (confirmed by detector log entries). Smart default for meeting provider still reads the Deepgram Keychain entry to pick `.deepgram` vs `.openai`.

**Smoke notes after rebuild:**
- Start a Teams meeting → panel pops (autoShow ON path).
- Click Stop → timer freezes on the recorded duration, status label transitions Chunking… → Transcribing N/M → Done while the timer stays put.
- Open Settings → Meeting section: provider picker shows `≈ $0.26 / hour…` for Deepgram, `≈ $0.36 / hour…` for OpenAI.
- Move Settings / Transcripts windows to another Space → both appear on the new Space.

**No version bump rationale:** these are local-only polish fixes. 0.7.0 just shipped; rolling a 0.7.1 right after for four small fixes feels premature. Batch with whatever lands next.

**Open follow-ups carried forward** (unchanged from 0.7.0 session): long-meeting (>2 GB) Deepgram fallback, persisting `MeetingAudioMixer` shifts so re-transcribe uses the real wall-clock offsets instead of `shift=0`, second-Mac TCC re-prompt UX after every ad-hoc install.

---

# Handoff — Vox state as of 2026-05-08 (Afternoon)

## Session 2026-05-08 — Deepgram diarized meeting transcription, sticky meeting panel, transcript UX cleanup (release 0.7.0)

**Status:** One feature release shipped today on top of the 0.6.8 timeout fix from earlier in the week. App runs end-to-end on this Mac; second Mac picks up via Sparkle on next check (or "Check for Updates…" in Settings). User must re-grant Mic / Input Monitoring / Accessibility after install — TCC re-prompts on every ad-hoc-signed release.

**Release shipped:**
- `v0.7.0` — Deepgram Nova-3 meeting transcription with per-speaker diarization, plus the surrounding UX fixes (sticky panel across Spaces, visible scrollbar, capped summary, exports include speaker labels).

**Why this changed:** prior meeting transcripts only carried a binary `local` (mic) vs `remote` (system audio) tag. The summarizer prompt then asked gpt-4o-mini to attribute names from context, which routinely mislabelled who said what — e.g. user kept being misidentified as the person they were addressing. Real diarization closes that gap.

**Architectural decisions made today:**
- **Single-stream mix into Deepgram, not dual-stream.** Each chunk through Deepgram would reset speaker numbering (diarization is per-request); chunking would also lose cross-speaker continuity. Instead, mic + system audio are mixed via `AVMutableComposition` (each track inserted at its wall-clock offset relative to the earliest audible content), the result is exported to a single m4a, and Deepgram is called once with `diarize=true&utterances=true`. Hard limit: 2 GB / file (Deepgram prerecorded API). A 43-min meeting at AAC 64 kbps is ~21 MB — comfortably below the cap. Long-meeting fallback deferred until someone actually hits it.
- **Deepgram replaces OpenAI on the meeting path; dictation untouched.** OpenAI Whisper stays the dictation backend. Meeting provider is `AppSettings.meetingProvider` with smart default: `.deepgram` if a Deepgram key is in Keychain (`account=deepgram-api-key`), else `.openai`. Existing OpenAI per-source pipeline is kept intact as the fallback path inside `runChunkAndUpload`.
- **Speaker IDs are opaque.** The summarizer prompt now forbids name-guessing — owners on action items are only attributed when a participant self-identifies in the transcript. The transcript view color-cycles a small palette by `speakerID % palette.count` so the eye can track who's talking without us pretending to know names.
- **Re-transcribe is a manual per-meeting button**, not an auto-migration. Existing meetings keep their original Whisper transcript until the user clicks "Re-transcribe (Deepgram)" in the transcript browser. The button reruns the pipeline against retained `audio.m4a` + `mic.m4a` (or whichever still exists), replaces `segments` + `summary` in place, and persists. No-op if both audio files have been purged (configurable retention sweep deletes them after 1 month by default).
- **Summary footprint capped, not collapsed by default.** First implementation showed `Text(summary)` with no height limit, which on long meetings pushed the segment list off screen. Settled on `ScrollView(...).frame(maxHeight: 180)` so the summary stays expanded by default but can't dominate the window. DisclosureGroup still allows full collapse.

**Key code landmarks added/changed today:**
- `Sources/vox/STT/DeepgramTranscriber.swift` — **new.** Single-shot batch call to `https://api.deepgram.com/v1/listen?model=nova-3&diarize=true&utterances=true&punctuate=true&smart_format=true&language=en`. Sends raw audio bytes with `Content-Type: audio/m4a` and `Authorization: Token <key>`. Parses `results.utterances[]` (each has `start`, `end`, `transcript`, `speaker`) into `[TranscriptSegment]` with `speakerID` populated. Skips empty utterances. Hard-fails with `fileTooLarge` over 2 GB.
- `Sources/vox/Meeting/MeetingAudioMixer.swift` — **new.** `AVMutableComposition` with one mutable audio track per source. Each track inserted at its `startTime` (seconds) on the composition timeline. Exports via `AVAssetExportSession(presetName: AVAssetExportPresetAppleM4A)` to m4a. Used both at end-of-recording (with the live wall-clock shifts) and in `reTranscribeWithDeepgram` (with `shift=0` since the original timeline data wasn't persisted).
- `Sources/vox/STT/MeetingTranscriptionSession.swift` — provider switch at the top of `runChunkAndUpload`: when `providerProvider() == .deepgram` and a `deepgramTranscribe` closure is wired, branches to `runDeepgramPipeline` (silence-trim each stream → mix → single Deepgram call → save segments + summary). New public method `reTranscribeWithDeepgram(sessionID:)` for the per-meeting button. Existing OpenAI per-source loop kept verbatim for the `.openai` path. New typealias `DeepgramTranscribe = (URL) async throws -> [TranscriptSegment]`. The shared singleton wires both transcribe closures + `provider: { AppSettings.meetingProvider }`.
- `Sources/vox/Util/MeetingTranscriptStore.swift` — `TranscriptSegment.speakerID: Int?` (Codable backward-compat via `decodeIfPresent`; pre-0.7 segments decode with `speakerID = nil`).
- `Sources/vox/Util/AppSettings.swift` — `MeetingProvider` enum + `meetingProvider` setting. Smart default reads `KeychainStore(account: "deepgram-api-key")` once: present → `.deepgram`, absent → `.openai`. Once user picks explicitly, the chosen value is honored regardless of key presence.
- `Sources/vox/Meeting/MeetingSummarizer.swift` — prompt rewritten to handle both label spaces (`Speaker N` and `Local`/`Remote`) and forbid name-guessing without self-identification. `formatTranscript` switches to `Speaker N:` prefix when any segment carries a `speakerID`, falling back to `Local:`/`Remote:` otherwise — preserves the existing summarizer test (`testFormatTranscriptTagsLocalAndRemote`).
- `Sources/vox/App/MeetingTranscriptsWindow.swift` — speaker labels per segment using `speakerID` first; color-cycled palette (`[.blue, .purple, .orange, .pink, .teal, .indigo, .brown, .red]`). New "Re-transcribe (Deepgram)" button visible when the session is in a terminal state and either audio file still exists. Summary disclosure wrapped in `ScrollView(.vertical).frame(maxHeight: 180)` to cap its vertical footprint; transcript ScrollView gained `.scrollIndicators(.visible)` + bounded frame so the bar always renders. Plain-text and timestamped exports now group consecutive same-speaker turns and prefix `Speaker N:` (or `You`/`Other` fallback).
- `Sources/vox/App/MeetingHUDPanel.swift` — `panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` so the floating Meeting panel follows the user across virtual desktops and into full-screen apps. Verified manually.
- `Sources/vox/App/SettingsWindow.swift` — Deepgram API key field (Keychain `account=deepgram-api-key`) below the OpenAI key block. Provider picker added to the Meeting section.
- Test count: 281 (unchanged — segment Codable migration covered by existing decode tests; new `DeepgramTranscriber` and `MeetingAudioMixer` are I/O-bound and tested only via manual smoke).

**Manual verification done:**
- Built `dist/Vox.app` and `dist/Vox.dmg` (2.4 MB, length 2525569). EdDSA signature: `zWPmYfaBvQb1c+yriaiU482ZWqy3HSjxTAg5uTazN5hMSksmqJ07qstPmjPDr6eaxMe0ahO/B5cz1HK2USLBBA==`.
- User re-transcribed an existing 43-minute meeting (`649BC478-62CD-4EB9-ABA5-8845495249C2`) end-to-end. Speaker IDs assigned per voice; summary regenerated with the new prompt; user confirmed accuracy improved and ownership attribution is no longer wrong.
- Sticky meeting panel confirmed working across Spaces.
- Visible scrollbar in transcript browser confirmed.
- Summary cap at 180 pt confirmed not crowding the transcript list.
- Exports include `Speaker N` labels.

**Open issues / next-session candidates:**
1. **Long-meeting Deepgram fallback.** Single-request mix is bounded by Deepgram's 2 GB cap and a ~10-minute synchronous wait. For multi-hour meetings, switch to the WebSocket streaming endpoint or chunk + stitch with `keyterm` cross-chunk speaker matching. Not yet needed in practice.
2. **Summarizer truncation cuts the meeting tail.** `MeetingSummarizer.maxTranscriptChars = 60_000` truncates from the front-truncated end of the string with a marker. Action items often surface late in a meeting, so they get clipped. Either chunk + summarize hierarchically, or move to gpt-4o (larger context). Track real impact before changing.
3. **Re-transcribe wall-clock offset is `0`.** Live recordings know `systemStartedAt` / `micStartedAt` (recorded by the recorder objects); re-transcribes don't, since those weren't persisted. Streams overlap correctly enough for diarization, but the absolute timeline drifts by however long mic-vs-system stagger was at recording time. Would need a `TranscriptSession.streamShifts: [String: Double]?` field to fix. Low priority — diarization quality is unaffected.
4. **No cost telemetry for Deepgram.** `UsageTracker` only counts OpenAI calls. Deepgram pricing differs (Nova-3: $0.0043/min batch). User won't see a meeting's Deepgram cost in Settings → Usage. Add when needed.
5. **AGENTS.md** still untracked. Carries over from previous handoff.

**Process notes that carried over from earlier sessions (still true):**
- Sparkle EdDSA private key on this Mac (kumedaa Dev workstation). Cut releases from here.
- Don't `git commit` until manual smoke confirms working.
- `--no-gpg-sign` on every commit.
- After every Swift commit during manual testing, run `scripts/build-app.sh` and tell user to relaunch.
- TCC re-prompts on every ad-hoc-signed release. Notarization still deferred.

---

## Session 2026-05-05 — paste-last + verbatim shipping, meeting auto-detect + summary, code-review hardening, mic HAL-stall watchdog (releases 0.6.2 → 0.6.7)

**Status:** Six releases shipped over the day. App runs end-to-end on this Mac and the second one; both updated via Sparkle. Repo is now public at `andykumeda/vox`; GitHub Pages serves `docs/appcast.xml`. Next phase candidates listed at the bottom.

**Releases shipped (all on `origin/main`):**
- `v0.6.2` — Paste Last Transcription menu item + opt-in hotkey (Settings → Hotkeys). Outbound paste shortcut hardcoded to ⌘V (the previous user-configurable "Paste keystroke" was a footgun). Clipboard restore no longer skipped when prior clipboard was empty / non-string.
- `v0.6.3` — Clipboard restore delay bumped 0.4s → 1.5s and guarded with `NSPasteboard.changeCount` so slow apps (Slack, Electron, browser inputs) read the transcript before restore overwrites the clipboard.
- `v0.6.4` — Verbatim/literal prefix word now actually skips trigger expansion + LLM cleaner (the help.md docs claimed this worked since 0.6.0, but the implementation in `CleanupProcessor.stripVerbatimPrefix` was sitting uncommitted).
- `v0.6.5` — Meeting **auto-detect** + post-transcription **summary**. New `MeetingDetector` polls window titles every 3 s via `CGWindowListCopyWindowInfo` (Teams desktop incl. compact-view + 1:1 + channel meetings, Zoom, Webex, Slack huddle, Discord voice/video, Skype, browser-based Meet/Zoom/Webex). Pops the floating panel — never auto-records. New `MeetingSummarizer` calls gpt-4o-mini with a structured prompt (Summary / Key decisions / Action items) and renders the markdown as a disclosure at the top of the transcript browser. Both opt-in via Settings → Meeting; auto-detect default OFF, summary default ON. ~$0.0005/meeting for the summary.
- `v0.6.6` — Six code-review fixes (P1+P2):
  - **P1.1**: Meeting HUD's Record button bypassed `MeetingPreflight.gate()` (preflight lived in unused MenuBarController path). Gate now runs inside `MeetingTranscriptionSession.start()` itself with an injectable provider; tests pass `{ .success(()) }` to bypass.
  - **P1.2**: Silent files were reported as audible. `SilenceTrim` returned `(firstAudibleSec: 0, lastAudibleSec: totalDur)` when no sample exceeded the RMS threshold; `hasAudibleContent` was true for any silent file >100 ms. Added `hadAudibleSamples: Bool` field; gate requires it.
  - **P1.3 / P1.4**: Failed recorder start/stop pinned the session at `.recording` / `.chunking` permanently. Both paths now wrap the recorder call in do/catch, persist `.failed`, clear in-memory state, and rethrow.
  - **P2.1**: Tap-to-toggle on `.fn` / `.modifier` keys was ignored. `handleTapToggle` accepted only `keyDown`, but the dispatcher routes `flagsChanged` for those keys. Now accepts both with rising-edge detection (`tapModifierLastMatch`).
  - **P2.2**: `abs(int16Channel[f])` in AudioRecorder peak probe traps on `Int16.min`. Widened to Int before negating.
- `v0.6.7` — **Meeting mic watchdog.** A 35-min Teams meeting captured only the first 9:18 of the user's voice; the rest of `mic.m4a` was RMS=0 even with normal speech. macOS HAL went silent mid-session (Teams renegotiation / USB power management / exclusive-access contention) and `AVAudioRecorder` kept encoding zero PCM with no signal. Added a per-second peak-power watchdog (`isMeteringEnabled = true`, ≤ −50 dB floor); after 30 s of consecutive silence the watchdog tears down the recorder, archives its file as `<base>-partN.m4a`, and starts a fresh recorder writing to the original output URL. At stop(), parts + final file are concatenated via `AVMutableComposition` + `AVAssetExportSession` into a single m4a so the chunking pipeline is unchanged.

**Key code landmarks added/changed today:**
- `Sources/vox/Meeting/MeetingDetector.swift` — new. Window-title pollster + hysteresis state machine.
- `Sources/vox/Meeting/MeetingSummarizer.swift` — new. gpt-4o-mini chat-completions client with injectable HTTPSend; 60k char input cap.
- `Sources/vox/Meeting/MeetingMicCapture.swift` — gained watchdog, multi-part recovery, and AVMutableComposition concat at stop.
- `Sources/vox/Meeting/SilenceTrim.swift` — `AudibleBounds.hadAudibleSamples` Bool.
- `Sources/vox/Meeting/MeetingPreflight.swift` — `MeetingGateError` + `MeetingPreflight` + `MeetingBackendStatus` exposed `public` so `MeetingTranscriptionSession` can throw `.preflight(...)`.
- `Sources/vox/STT/MeetingTranscriptionSession.swift` — preflight gate inside start(); injectable `summarize`, `summarizeEnabled`, `preflight` providers; do/catch around recorder start/stop with state recovery; new `SessionError.preflight` and `.recorderStartFailed`.
- `Sources/vox/Hotkey/HotkeyMonitor.swift` — `tapModifierLastMatch` rising-edge state for `.fn`/`.modifier` tap-toggle.
- `Sources/vox/Audio/AudioRecorder.swift` — peak probe widens through Int.
- `Sources/vox/App/MeetingHUDPanel.swift` — onStart surfaces preflight errors as NSAlert; onStop logs (no longer swallows) on stop failures.
- `Sources/vox/App/MeetingTranscriptsWindow.swift` — Summary disclosure section.
- `Sources/vox/App/MenuBarController.swift` — wires `MeetingDetector` start/stop based on `AppSettings.autoShowMeetingPanel`; `dictationHistoryDidChange` listener refreshes the menu so "Paste Last Transcription" enables after first dictation; new `pasteLastHotkey` listener.
- `Sources/vox/App/SettingsWindow.swift` — auto-show toggle + summary toggle + paste-last-hotkey field; "Paste keystroke (sent to focused app)" field removed.
- `Sources/vox/Hotkey/Hotkey.swift` — `defaultPasteLast` (disabled by default).
- `Sources/vox/Util/AppSettings.swift` — `pasteLastHotkey`, `autoShowMeetingPanel`, `meetingSummaryEnabled`.
- `Sources/vox/Util/MeetingTranscriptStore.swift` — `TranscriptSession.summary: String?` (Codable backward-compat via `decodeIfPresent`).
- `Sources/vox/Util/DictationHistoryStore.swift` — `last()` accessor.
- `Sources/vox/Text/TextInjector.swift` — outbound paste hardcoded to ⌘V; `changeCount`-guarded restore at +1.5 s.
- `Sources/vox/Text/CleanupProcessor.swift` — `stripVerbatimPrefix` (regex anchored at start; case-insensitive; mid-sentence "verbatim" left intact).
- `scripts/dump-windows.swift` — debug helper. Prints owner+title for every on-screen window. Note: a terminal-launched script needs Terminal to have Screen Recording permission for titles to populate (Vox.app has it).
- `Tests/voxTests/MeetingDetectorTests.swift` — pattern coverage incl. real-world Teams compact-view title.
- `Tests/voxTests/MeetingSummarizerTests.swift` — chat-completions client incl. legacy JSON decode for `TranscriptSession.summary`.
- `Tests/voxTests/SilenceTrimTests.swift` — silent / short-blip / valid cases for the new `hasAudibleContent` semantics.
- Test count: 281 (was 249 at session start).

**Infra changes:**
- Repo flipped public during the session so Sparkle could anonymously download release DMGs (private repo blocks unauth asset fetches with a 302 to a 404).
- GitHub Pages re-enabled twice (`gh api -X POST repos/andykumeda/vox/pages -f 'source[branch]=main' -f 'source[path]=/docs'`); something in the GH UI flow had toggled it off.
- `Pages build and deployment` workflow occasionally reports failure when a push cancels the previous build mid-flight; a `gh run rerun --failed` redeploys cleanly. Not a real regression.
- `tools/` (local STT bench dir with `.env` holding provider keys) is in `.gitignore` so accidental `git add .` won't leak keys.
- Repo description updated: "Push-to-talk voice dictation for macOS … OpenAI gpt-4o-mini-transcribe." (was "Groq whisper-large-v3" — stale.)
- Legacy `groq-api-key` Keychain entry deleted on this Mac. Vox only reads `com.andykumeda.vox / openai-api-key`.
- README rewritten for the post-0.5 surface (Meeting / Dictionary / Smart Cleanup / Hotkeys table / Releasing section / Sparkle requirements). UPDATING.md leads with Sparkle, manual DMG drag is fallback. help.md covers paste-last, verbatim/literal, auto-detect, summary.

**Architectural decisions made today:**
- Auto-detect uses **window-title polling**, not CoreAudio per-process input monitoring (which is macOS 14.4+). Keeps minSystemVersion at 13.0. Polling cost is small (~3 s interval, CGWindowListCopyWindowInfo) and matches the user's mental model ("when a meeting window opens, pop the panel"). Browser tab detection is conservative — bare "Microsoft Teams" was dropped because every Teams chat tab matches it; web-meeting patterns now require URL fragments like `meet.google.com`, `Zoom Meeting`, or Teams join-URL paths.
- Recording is **never auto-started.** The HUD's Record button still requires a deliberate click. Consent + dictation-mutex stay on the panel.
- Summary is **persisted on the TranscriptSession**, not regenerated on view. One-shot $0.0005 cost; subsequent opens are free. Failures are logged + swallowed — a missing summary is non-fatal.
- Mic watchdog **does not auto-stop** the meeting on persistent stalls. It logs `Mic stalled and could not be restarted` and sets `lastFailureReason`. Stopping mid-meeting would lose all subsequent system-audio capture too. Better to keep the meeting going and warn at the end.
- Outbound paste shortcut is **hardcoded to ⌘V**. The previous user-configurable `pasteHotkey` was a real-world footgun: rebinding it to anything else silently broke paste in apps that only honor ⌘V. The keychain entry is preserved for backward-compat reads but no UI exposes it.

**Open issues / next-session candidates:**
1. **Mic-stall recovery beyond restart.** If the HAL stays stuck after recorder restart (Teams holds exclusive access permanently), watchdog logs `Mic stalled and could not be restarted` and `lastFailureReason` is set, but the user voice is still lost. Next step: force CoreAudio to re-resolve the default input device (`kAudioHardwarePropertyDefaultInputDevice`), or fall back to AVAudioEngine + tap → AVAssetWriter pipeline (more controllable than AVAudioRecorder). Worth a code spike before promising "always recovers."
2. **Auto-show false positives** are bounded but not zero. Pattern matching is substring-based and case-sensitive. Edge: someone dictates the literal text "Zoom Meeting" into a long-running browser tab and the panel pops. Heuristic — accept the cost; the user dismisses it. If complaints arrive, tighten patterns or require a process-name allowlist alongside.
3. **Meeting summary quality on long meetings.** Input is capped at 60k chars (~~10k words). Real-world meetings can run longer; truncation marker is appended, but the summary loses the tail. Options: chunk + summarize hierarchically, or switch to gpt-4o (full) with its larger context window for long meetings.
4. **`AGENTS.md`** keeps appearing as untracked in `git status`. Probably a tool that auto-creates it. Either commit it or add to `.gitignore`. Not investigated.
5. **Dictation regression** still emits `failure_rate=0.0 quality_score=1.0` consistently; baseline is healthy. Worth re-checking after the next round of CleanupProcessor changes.
6. **Notarization.** TCC re-prompts on every ad-hoc-signed update remain the worst part of the upgrade UX. Apple Developer Program ($99/yr) + notarization would fix it. Still deferred.

**Process notes (for future sessions):**
- Sparkle EdDSA private key is on this Mac (kumedaa Dev workstation). Releases must be cut from here.
- Standing rule: don't `git commit` until manual smoke confirms working. Tests + clean build are necessary, not sufficient.
- Use `--no-gpg-sign` on every commit (pinentry fails in non-tty shells; durable permission granted).
- After every Swift commit during manual testing, run `scripts/build-app.sh` and tell the user to relaunch Vox. They won't pick up the change otherwise.
- For diagnostic dumps that need on-screen window titles populated, run inside the Vox.app context (or grant Terminal Screen Recording).

---

## Session 2026-04-30 — M2 multi-source capture, main window UI, new icon, releases 0.4.0 / 0.5.0 / 0.5.1

**Status:** Three releases shipped today. App runs end-to-end on both Macs (kumedaa + the second one); other Mac auto-updated via Sparkle and is functional after re-granting Accessibility. Next phase queued: meeting summarization (TL;DR via gpt-4o-mini), per stakeholder request.

**Releases shipped (all on `origin/main`):**
- `v0.4.0` — meeting M2: parallel mic + system audio capture, wall-clock timeline alignment, silence trim, Whisper language pin, distinct red meeting menu icon, multi-modifier hotkey capture fix, audible cue on suppressed Fn during meeting.
- `v0.5.0` — main window UI with sidebar nav (Home / Dictionary / Meeting / Settings / Help). Auto-opens on launch, hides on close. Home shows stats + recent dictations + recent meetings. Dictation history persisted at `~/Library/Application Support/Vox/DictationHistory/history.json` with configurable retention (forever / 1y / 90d / 30d). Whisper repetition hallucination filter ("yeah, yeah, yeah, ..." 30s walls). Keychain reads cached in process memory.
- `v0.5.1` — new chrome-V app icon. Menu bar shows the actual icon (cyan in prose, amber/gold in command/terminal) with red/orange dot badge for recording/transcribing. Mode toggle hotkey now flips directly between prose ↔ command on a single press (skips .auto so the change is always visible).

**Key code landmarks added today:**
- `Sources/vox/Meeting/MeetingMicCapture.swift` — `AVAudioRecorder` mic capture, conforms to `MeetingAudioRecording`.
- `Sources/vox/Meeting/SilenceTrim.swift` — PCM scan at -46 dBFS RMS, trims leading/trailing silence via passthrough export. Used per stream before chunking.
- `Sources/vox/Util/Log.swift` — shared `dlog` (was private to MenuBarController).
- `Sources/vox/Util/DictationHistoryStore.swift` — singleton, JSON file, retention enforced on every record().
- `Sources/vox/App/MainWindow.swift` — NSWindow + SwiftUI NavigationSplitView with sidebar.
- `Sources/vox/App/DictionaryView.swift` — extracted from SettingsView.
- `Sources/vox/App/UpdaterAccess.swift` — process-wide handle to Sparkle's updater controller.
- `Resources/AppIcon.svg`, `Resources/AppIcon-Command.svg` — sources for both menu-bar variants.
- `Resources/AppIcon-Command.png` — 72×72 amber variant for terminal-mode menu bar (bundled by build-app.sh).

**Architectural decisions made today:**
- Meeting transcripts: two parallel streams (system + mic), tagged segments interleaved by `startTime` after wall-clock alignment. Each segment carries `source: .local | .remote`. Sort tie-breaker prefers local first.
- Hallucination handling: drop segments past audible duration cap, drop low-unique-ratio repetitions. Whisper API request now pins `language=en` and `temperature=0`.
- HotkeyRecorder: defers single-modifier commit until release (so multi-modifier combos can be entered). `HotkeyRecorder.isCapturing` static gate suppresses global HotkeyMonitor dispatch while configuring.
- Menu bar dropdown trimmed to: Home / Check for Updates / Help / Quit. Meeting commands moved to main-window Meeting tab.

**Open issues / next-session candidates:**
1. **Meeting summarization** — user explicitly requested as next phase. Add a TL;DR field to `TranscriptSession`, generate via OpenAI gpt-4o-mini after transcription completes, render in MeetingTranscriptsView's detail pane. Cost: ~$0.0005 per meeting. Make optional via setting (default on).
2. **TCC stale grants after Sparkle update** — Accessibility specifically gets dropped on every cdhash change because the build is ad-hoc-signed `vox-dev`. After the 0.5.1 update on the other Mac, dictation broke until `tccutil reset Accessibility com.andykumeda.vox` + re-grant. Permanent fix: notarized Developer ID build ($99/yr Apple Developer enrollment).
3. **Mic bleed during meetings** — user already aware; works around with headphones.
4. **Per-chunk silence skip** before sending to Whisper would prevent repetition hallucinations at source (cheaper than the post-filter).
5. **`/usr/bin/log show` for vox** — partial, dlog now writes to `~/Library/Logs/vox.log` for both dictation and meeting paths.

**Sparkle release flow on this machine (kumedaa):** verified working end-to-end. Private EdDSA key in login keychain, `Private key for signing Sparkle updates`, account `ed25519`. Standard flow: bump Info.plist → commit + tag → `make-dmg.sh` → `sign_update` → `gh release create` → prepend appcast.xml → push. ~10 min Pages CDN before the other Mac sees the new entry.

**Tests at end of session:** 244/244 passing. Dictation regression baseline: failure_rate=0.0, quality_score=1.0, latency≈2-3ms (within noise).

**Branch state:** `main` clean, in sync with `origin/main`. Last commit: `release: appcast 0.5.1`. `tools/` (stt-bench) still untracked.

---

## Session 2026-04-29 Evening — M2 polish + bug hunt (paused mid-debug)

**Status:** M2 fully shipped (commits up through `9db3111`, all on `origin/main`). Then a series of fixes for issues surfaced by the first manual smoke. Last attempted recording showed two stuck states. **Next session must finish the debug loop before declaring M2 production-ready.**

**Polish landed and pushed in this session:**
- `361ba20` — menu rebuilds when Meeting Mode toggle flips (was static after launch).
- `dc91e89` — SCStream needs non-zero `width`/`height` even for audio-only; added delegate logging + `TranscriptSession.failureReason` field surfaced in detail pane.
- `6e4f0a7` — Meeting toggle hotkey, default `Cmd+Shift+M` (tap-toggle), wired through `HotkeyMonitor` like `modeToggle`. Editable in Settings → Hotkeys.
- `7da4112` — Floating HUD panel near menu bar during recording (red dot, `mm:ss` elapsed, stop button). NSPanel `.borderless`, `.nonactivatingPanel`, level=`.statusBar`. Self-dismisses when session goes inactive via 0.5s polling timer.
- `9db3111` — Auto-prompt Screen Recording permission on first Meeting Mode toggle (`CGRequestScreenCaptureAccess()`). Added "Open Screen Recording Settings" button to existing Permissions section.
- `bd9c007` — Surface zero-sample-buffer capture failure cleanly (was crashing chunker with `Cannot Open / media may be damaged`).
- `0cd597d` — Lazy AVAssetWriter init from first sample buffer's CMFormatDescription. SCStream emits Float32 PCM in its own native rate/layout (typically 48kHz stereo); the prior 16kHz mono AAC settings caused `Cannot Encode Media` (writer status=3) once 984 buffers had streamed in.

**Still broken — pick up here next session:**

1. **Singleton not clearing on terminal status** (just observed). After a session completes/fails/cancels, `MeetingTranscriptionSession.shared.session` is never reset to nil, so the next `start()` throws `SessionError.alreadyActive` ("A meeting session is already active.").
   - Fix in `Sources/vox/STT/MeetingTranscriptionSession.swift`: in `runChunkAndUpload`, after the final `updateSession` that flips status to `.completed`/`.cancelled`/`.failed`, also clear the singleton's `session` var. Also clear in the early-return paths in `stop()` (capture failure / chunking failure).
   - Or: simpler — check `session?.status` in `start()`. If terminal (`.completed`/`.cancelled`/`.failed`), clear and proceed. If active (`.recording`/`.chunking`/`.transcribing`), throw alreadyActive.
   - Tests: `MeetingTranscriptionSessionTests` need a new case `testCanStartSecondSessionAfterFirstCompletes` to lock this in.

2. **Probably still need to verify the lazy-writer fix actually produced a playable .m4a.** Today's last test never got past the "alreadyActive" guard, so we don't know if `0cd597d` actually solves the `Cannot Encode Media` case end-to-end. Re-run after the singleton fix, with audio playing through speakers.

3. **`/usr/bin/log show` for vox doesn't show our `NSLog("[vox] MeetingAudioCapture …")` lines** unless `--info` is passed. Consider switching MeetingAudioCapture to write through the same `dlog` helper that `MenuBarController` uses (writes to `~/Library/Logs/vox.log`). Currently `dlog` is private to `MenuBarController.swift` — promote to file-scope or move to a shared `Sources/vox/Util/Log.swift`.

4. **`_LSOpenURLsWithCompletionHandler() failed with error -600`** — user saw this in the terminal during today's testing but did not nail down which click triggered it. Probably stale Vox process during `open dist/Vox.app`. Diagnose on next launch loop if it recurs.

**Test suite at end of session:** 239/239 passing. Dictation regression baseline: failure_rate=0.0, quality_score=1.0, latency≈4.5ms (within noise).

**Branch state:** `main` clean, in sync with `origin/main` (last push includes the lazy-writer fix). `tools/` (stt-bench) still untracked.

**Spec + plan docs (unchanged today):**
- `docs/superpowers/specs/2026-04-29-meeting-transcription-m2-design.md`
- `docs/superpowers/plans/2026-04-29-meeting-transcription-m2-implementation.md`

---

## Session 2026-04-29 PM — Meeting Transcription M2 pipeline shipped

**Status:** All M2 deliverables implemented and committed on `main`. `swift build` clean. Full suite passes: 239 tests (was 221), 0 failures. Dictation regression baseline holds: `failure_rate=0.0 quality_score=1.0 latency_ms≈4.5` (was 2.5; small jitter, well within tolerance). `dist/Vox.app` built via `./scripts/build-app.sh`.

**What landed (commits in order):**
- `Tests/voxTests/Support/URLProtocolStub.swift` — reusable HTTP mock for tests.
- `Sources/vox/Util/MeetingTranscriptStore.swift` + `TranscriptSegment`/`TranscriptSession` Codable models. Atomic JSON writes under `~/Library/Application Support/Vox/MeetingTranscripts/<uuid>/`. `recoverInFlightSessions()` cold-recovery sweep.
- `Sources/vox/Util/AppSettings.swift` — added `meetingRetainAudio` (default off).
- `Sources/vox/App/SettingsWindow.swift` — "Keep audio recording after transcription" toggle in Meeting (Beta) section.
- `Sources/vox/STT/OpenAITranscriber.swift` — additive `transcribeMeetingChunk(fileURL:offsetSeconds:apiKey:endpoint:urlSession:)` returning `[TranscriptSegment]` from Whisper `verbose_json`. Promoted `sendWithRetry` to `static` with optional `session` param so tests can inject `URLProtocolStub`. Existing dictation `transcribe(...)` untouched.
- `Sources/vox/STT/MeetingChunker.swift` — splits .m4a into ordered 5-min AAC chunks via `AVAssetExportSession`/`AVAssetExportPresetAppleM4A`.
- `Sources/vox/Meeting/MeetingAudioCapture.swift` — `MeetingAudioRecording` protocol + `SCStream` wrapper (macOS 13+) that writes AAC m4a via `AVAssetWriter`. Excludes Vox's own audio.
- `Sources/vox/STT/MeetingTranscriptionSession.swift` — singleton state machine: `idle → recording → chunking → transcribing → completed/cancelled/failed`. Serial upload (parallelism=1), infinite retry on `URLError` transport codes with backoff `[1,2,4,8,16,30]s`, user-cancellable via `Task.cancel()`. Exposes `isRecording`, `isActive`, `activeSessionID`, `statusSnapshot`, `waitForCompletion()`.
- `Sources/vox/Meeting/MeetingPreflight.swift` — replaced stub `backendStatusProvider` with `liveStatus(for:)` using `CGPreflightScreenCaptureAccess()`. New `MeetingGateError` cases: `.permissionDenied(.screenRecording)`, `.captureFailed`, `.chunkingFailed`.
- `Sources/vox/App/MenuBarController.swift` — `DictationMutex.isBlocked` injectable hook (early-returns Fn-hold when meeting recording). Live `Start Meeting Transcript` (gates dictation-active via `state == .recording`), `Stop Meeting Transcript` (calls session, opens transcripts window), new `Show Meeting Transcripts…` item.
- `Sources/vox/App/MeetingTranscriptsWindow.swift` — lazy NSWindow + SwiftUI sidebar (sessions list with status badge + cancel button) + detail (segments with `mm:ss` timestamps) + Export menu (Plain / Timestamped Text) + Delete (NSAlert confirm).
- `Sources/vox/App/AppDelegate.swift` — `MeetingTranscriptStore().recoverInFlightSessions()` on launch.
- Tests: `MeetingTranscriptStoreTests` (6), `OpenAITranscriberMeetingTests` (3), `MeetingChunkerTests` (2 with generated AAC fixture via `AVAudioFile`), `MeetingTranscriptionSessionTests` (5: happy/transient-retry/cancel/audio-retain×2), `MeetingMutexTests` (2). Total +18 tests.

**How to manually verify (run from this Mac):**
1. `pkill -9 -f 'Vox.app/Contents/MacOS/vox'`
2. `open dist/Vox.app`
3. Settings → Meeting Transcription (Beta) → enable Mode + acknowledge consent. Verify "Keep audio recording after transcription" toggle present (default off).
4. Menu bar → Start Meeting Transcript. Approve Screen Recording prompt if shown. Hold Fn — verify dictation does NOT activate.
5. Play 30s of speech audio. Stop Meeting Transcript. Window opens with `Transcribing N/M` then `Done`.
6. Export → Plain Text / Timestamped Text → verify file content.
7. Cancel mid-transcribe path: record 12+ min, click `(x)` while transcribing — confirms `.cancelled` with partial segments.
8. Audio retain toggle: enable, record short meeting, confirm `audio.m4a` exists in `~/Library/Application Support/Vox/MeetingTranscripts/<uuid>/`. Disable, record another, confirm not retained for the new one.

**Known limitations / M3 candidates:**
- No telemetry or redaction.
- No live transcription during recording (locked spec decision: end-of-meeting only).
- No background continuation if app quits mid-recording — `audio.m4a` truncates; cold-recovery flips status to `.failed` on next launch.
- Meeting + dictation are mutually exclusive via `DictationMutex` + `state == .recording` checks.

**Outstanding pre-existing items (not part of M2):**
- 0.3.3 DMG/appcast/GH Release blocked on AKsMini for Sparkle EdDSA signing.
- `tools/` (stt-bench) untracked locally; lives on `feat/stt-bench` branch.

**Spec + plan docs:**
- `docs/superpowers/specs/2026-04-29-meeting-transcription-m2-design.md`
- `docs/superpowers/plans/2026-04-29-meeting-transcription-m2-implementation.md`

---

## Session 2026-04-29 PM — Meeting Transcription M1 scaffolding shipped

**Status:** Committed as `12d508e` on `origin/main`. All M1 deliverables implemented except AudioRecorder backend abstraction (deferred to M2 — see plan note). Builds clean (`swift build` ok). Full suite passes (`swift test` → 221 tests, 0 failures, was 209). Dictation regression baseline still: failure_rate=0.0, quality_score=1.0, latency=4ms.

**Files changed:**
- `Sources/vox/Util/AppSettings.swift` — added `MeetingCaptureBackend` enum + 3 keys (`meetingModeEnabled`, `meetingConsentAcknowledged`, `meetingCaptureBackend`). All default-off, no migration.
- `Sources/vox/Meeting/MeetingPreflight.swift` (new) — `MeetingGateError` typed errors, `MeetingBackendStatus` (`.pendingImplementation` default), `MeetingPreflight.gate(...)` pure-function gate. `backendStatusProvider` is the injection point M2 will replace with a real ScreenCaptureKit availability check.
- `Sources/vox/App/MenuBarController.swift` — Start/Stop Meeting Transcript menu items, only inserted when `meetingModeEnabled=true`. Action runs the gate; on success shows a "lands in M2" alert; on failure shows the gate error's `userMessage`.
- `Sources/vox/App/SettingsWindow.swift` — new "Meeting Transcription (Beta)" section: enable toggle, consent toggle (visible only when enabled), backend status row.
- `Tests/voxTests/MeetingPreflightTests.swift` (new) — 6 cases covering each gate denial path + the success path + the default-status invariant.
- `Tests/voxTests/MeetingSettingsTests.swift` (new) — 5 cases: defaults are off, round-trip, no perturbation of dictation toggles.
- `docs/superpowers/plans/2026-04-29-meeting-transcription-additive.md` — M1 checkboxes ticked; AudioRecorder refactor explicitly deferred to M2 with rationale.

**Why AudioRecorder refactor was deferred:** The plan called for a backend abstraction in M1, but the only existing consumer is the microphone dictation path. Premature abstraction with one implementation violates the no-regression rule (any reshuffle of `AudioRecorder` risks the primary dictation flow) and the simplicity-first guideline. M2 introduces the second backend (ScreenCaptureKit system audio) — that is when the abstraction earns its keep. Keep this in mind when starting M2: the abstraction shape should be designed against both real backends, not invented in advance.

**Next action for next engineer session (M2):**
1. Implement system-audio capture via `ScreenCaptureKit` (macOS 13+, `SCStream` + audio sample handler). Wire it behind a `MeetingCaptureBackend` protocol that the dictation `AudioRecorder` does NOT need to conform to (additive only).
2. Replace `MeetingPreflight.backendStatusProvider` with a live check that returns `available: true` once entitlements + permissions are satisfied.
3. Build `Sources/vox/STT/MeetingTranscriptionSession.swift` per plan M2 deliverables.
4. Add transcript persistence + UI list + export.
5. Run `scripts/run-dictation-regression.sh` before commit; CI gate is on `pull_request`.

**Outstanding pre-existing items not part of M1:**
- 0.3.3 release blocked on AKsMini for Sparkle EdDSA signing (see "0.3.2 SHIPPED + uncommitted 0.3.3 transport-retry fix" section below — note: that fix is now committed as `7bc8cad` on main; only the DMG/appcast/GH Release remain).
- `tools/` (stt-bench) untracked locally on `main` workstation; lives on `feat/stt-bench` branch. Merge decision still open.

---

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

## Session 2026-04-29 PM — 0.3.2 SHIPPED + 0.3.3 transport-retry fix committed (release artifact pending)

**Status:**
- **0.3.2 is fully released.** GitHub Release `v0.3.2` exists with `Vox.dmg` (2,565,662 bytes), Sparkle EdDSA signature `WW4usR9mIl/xkNMz1P1MPZfKoMxl+bNKDTGx1IZXv/tnR08vR9zmFEKjHWdUJs0CrprNmZzKkUUGB/LIVORrDw==`, `docs/appcast.xml` updated (commit `d8e5488`), Pages CDN serving the new appcast.
- **0.3.3 transport-retry fix is committed** as `7bc8cad` on `main` (30s request timeout + single retry on transient URLErrors). **No release artifact yet:** no DMG, no appcast entry, no GitHub Release. AKsMini must run `make-dmg.sh` + `sign_update` + `gh release create v0.3.3` (or just bump to 0.3.4 if more changes accumulate first).

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

### 0.3.3 candidate fix (committed `7bc8cad`, release artifact pending)

The fix below is now on `main`. XCTest verified locally (full suite passes). Only the DMG + Sparkle signature + GH Release + appcast entry remain.

`Sources/Vox/STT/OpenAITranscriber.swift`:

- `request.timeoutInterval = 30.0` (was 20.0) — gives long dictations more headroom but still surfaces stalls quickly.
- Extracted send into `private static func sendWithRetry(_:)` — single retry (max 2 attempts total, 500ms backoff) on `.timedOut`, `.networkConnectionLost`, `.dnsLookupFailed`, `.notConnectedToInternet`, `.cannotConnectToHost`. Other `URLError` codes and non-URLError errors throw immediately (no retry on auth or HTTP errors).

Worst-case latency: 30s × 2 + 500ms = ~60.5s. That's generous but the alternative is still the silent-hang user reported. If the retry feels too slow in practice, drop to 15s timeout × 2 attempts.

Build verified on kumedaa (`swift build` clean, full `swift test` suite passes — 221/221 as of this session). Smoke-test live before release: hold Fn → speak → release on a Wi-Fi flap if you can simulate one.

To ship as 0.3.3 (or fold into a higher version if more lands first):

```sh
# On AKsMini:
cd ~/Dev/vox && git pull
swift test                 # confirm pass (currently 221)
# Bump CFBundleShortVersionString=0.3.3, CFBundleVersion=7 in Resources/Info.plist
git add Resources/Info.plist
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
