# Vox Handoff

Last updated: 2026-07-21

## Current state

- Project root: `/Users/andy/Dev/vox` on Mac mini `AKsMini`.
- Branch/base: `main` at `e93221e`, synchronized with `origin/main` and the
  independent MacBook clone.
- No version bump, tag, DMG, appcast edit, or release was made.
- Installed mini bundle: `/Applications/Vox.app`, version `0.7.28` build `47`,
  executable UUID `28CC379D-B5DA-324F-9A9F-5F28E9B9E3A7` (`arm64`). Its
  LaunchAgent is running as `com.andykumeda.vox`.
- MacBook `AK's MBPro` is reachable from the mini as SSH host `mbpro`. A clean
  clone exists at `/Users/andy/Dev/vox` on the MacBook, with repository-local
  Git author configuration. Codex Desktop is displayed on the MacBook while
  this task's remote workspace executes on the mini.
- MacBook `/Applications/Vox.app` is version `0.7.28` build `47`, signed by its
  machine-local `vox-dev` identity, and supervised by the running
  `com.andykumeda.vox` LaunchAgent.

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

- The MacBook has Xcode 27.0 selected at
  `/Applications/Xcode.app/Contents/Developer` and a valid machine-local
  `vox-dev` signing identity (`8D0712F49BB55EAD8508CD3C7A0166F0898C20F2`).
- `codesign --verify --deep --strict /Applications/Vox.app` passes and its
  designated requirement is pinned to the MacBook identity.
- OpenAI and Deepgram credentials are stored as separate login-keychain entries
  for service `com.andykumeda.vox`; no credential values are in the repository.
- After restart, MacBook logs confirm hotkey monitoring, Accessibility,
  Microphone, and OpenAI key warmup (`has_key=true`). The user reports the app
  otherwise working correctly. A live Deepgram meeting request was not run as
  part of credential transfer.
- Continue using Git push/pull between independent local clones. Do not place a
  live working tree in iCloud Drive or another file-sync service.

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

1. Optionally live-smoke a Deepgram-backed meeting on the MacBook when that
   provider is next used; key presence is verified but no paid API request was
   made during setup.
2. Recreate or restore a persistent mini `vox-dev` identity interactively before
   its next app build; rebuild and re-grant permissions once if the identity
   changes.
