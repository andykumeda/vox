# Vox Handoff

Last updated: 2026-07-20

## Current state

- Project root: `/Users/andy/Dev/vox` on Mac mini `AKsMini`.
- Branch/base: `main`, with four focused audit/latency/documentation commits on
  top of `7877d45`. The commits are ready to push; the interactive MacBook
  bootstrap remains incomplete.
- No version bump, tag, DMG, appcast edit, or release was made.
- Installed mini bundle: `/Applications/Vox.app`, version `0.7.28` build `47`,
  executable UUID `28CC379D-B5DA-324F-9A9F-5F28E9B9E3A7` (`arm64`). Its
  LaunchAgent is running as `com.andykumeda.vox`.
- MacBook `AK's MBPro` is reachable from the mini as SSH host `mbpro`. A clean
  clone exists at `/Users/andy/Dev/vox` on the MacBook, with repository-local
  Git author configuration. Codex Desktop is displayed on the MacBook while
  this task's remote workspace executes on the mini.

## Reviewed changes

- Dictation uses WAV-duration-aware request timeouts with one monotonic hard
  deadline shared by retries. The build script resolves SwiftPM's actual bin
  path and verifies built/bundled Mach-O UUIDs.
- Keychain access is serialized and cached; startup warms the dictation key.
- Logs rotate at 5 MiB and record transcript/window-title metrics rather than
  user-authored text.
- Dictation history preserves malformed/unreadable data and posts notifications
  only after successful writes.
- Meeting preflight follows the selected provider; stop/start failure recovery,
  delayed-summary scoping, retranscription rollback, delete/update races, and
  recursive audio retention cleanup are covered by regression tests.
- Obsolete `pasteHotkey`, one-choice meeting backend, and duplicate meeting
  retention settings were removed. Settings disk-usage scans run off-main.
- Hotkey capture ownership and privileged relocation path quoting were hardened.
- Active instructions were audited: full Xcode is now required, two-Mac local
  clone workflow is documented, stale release-host/log/test-count guidance was
  corrected, and historical remote failures are labeled as historical.

## Verification

- `swift test`: 380 tests, 0 failures.
- `./scripts/run-dictation-regression.sh`: passed; 7 fixtures,
  `failure_rate=0.0`, `quality_score=1.0`.
- `swift build -Xswiftc -strict-concurrency=complete`: passed with seven known
  Swift 6 migration warnings around existing singleton/shared mutable state.
- `git diff --check` and shell syntax checks passed.
- Manual integration evidence for the exact installed UUID is present after the
  July 10 build: many successful dictation/paste cycles through July 20,
  multiple long recordings reaching the adaptive timeout cap, successful Paste
  Last events, and a July 15 41-minute meeting that completed with 672 segments
  and a generated summary.

## Two-Mac setup status

- The MacBook has only `/Library/Developer/CommandLineTools`; a clean `swift
  test` correctly fails because `SwiftUIMacros.StateMacro` is absent.
- Xcode redownload was initiated in the MacBook App Store and paused at the
  Apple Account sign-in sheet. The user must complete that credential step.
- After Xcode installs: launch it once, select it with `sudo xcode-select -s
  /Applications/Xcode.app/Contents/Developer`, then run `./scripts/setup.sh`
  locally on the MacBook. The login-keychain password and TCC prompts require
  direct user interaction.
- The MacBook currently has no `vox-dev` identity and no installed Vox bundle.

## Signing caveat

- After the macOS 27 update, the mini no longer reports a valid `vox-dev`
  identity in its login keychain. The installed app still runs with its pinned
  designated requirement referencing certificate SHA-1
  `406E1921DF57A0FC9CFE620F5FBC0524D1BB201E`, but the certificate/private key is
  unavailable to sign a new build.
- Do not run `build-app.sh` on the mini until a persistent identity is restored;
  it would fall back to ad-hoc signing and replace the installed bundle. Creating
  a new identity changes the requirement and requires re-granting TCC once.
- Sparkle EdDSA release signing remains Mac-mini-only. Do not cut a release as
  part of this setup task.

## Next steps

1. Complete the MacBook App Store sign-in and Xcode installation.
2. Run the MacBook's interactive `setup.sh`, grant Microphone, Input Monitoring,
   Accessibility, and Screen Recording as needed, then smoke dictation/paste.
3. Recreate or restore a persistent mini `vox-dev` identity interactively before
   its next app build; rebuild and re-grant permissions once if the identity
   changes.
4. Pull the committed source/docs into the MacBook clone after they are pushed.
