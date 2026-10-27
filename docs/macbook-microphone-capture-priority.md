# P1 — MacBook USB-to-built-in capture failure

Reported 2026-10-27. Owner: Codex. Overall state: Verified for the reported built-in-keyboard/built-in-microphone incident.
Priority: P1 follow-up for repeated USB disconnect/reconnect validation, ahead of
deferred transcription features. The reported incident is recovered; repeated route
cycles and external-keyboard hotkey compatibility remain unverified.

| Work | State | Acceptance / scope | Verification |
| --- | --- | --- | --- |
| Capture incident diagnosis | Verified | Distinguish short release, no callbacks, converter failure, and hotkey release | MacBook 0.7.78/102 logs: USB delivered frames; fallback selected; next attempt stopped about 0.1 s after start with no callback; later missing Fn events traced to external-keyboard use by user |
| Early-release classification | Verified | AudioRecorder and MenuBarController: empty release during Starting cancels; timeout, conversion and save errors remain failures | Original regression failed with the screenshot error; 526 macOS + 21 VoxCore tests pass; seven dictation fixtures quality 1.0/failure rate 0.0 |
| Local production deployment | Deployed | Unique unreleased 0.7.79/103 signed install/restart on Mini and MacBook | Mini and MacBook installed/restarted; strict signatures pass, executable SHA-256 matches; public Sparkle stays 0.7.78/102; no push/publication requested |
| Actual microphone-switch validation | In progress | Hold Fn for 3–5 s and dictate on built-in after USB disconnect, repeat; reconnect USB and repeat; verify raw and converted frames plus transcription | Two built-in fallback dictations completed on 0.7.79/103 using built-in keyboard; repeated USB reconnect cycles remain pending |

Scope reaches AudioRecorder.captureFailure, its MenuBarController completion caller,
recorder route regressions, README, Help, bundle identity, and handoff. No engine
lifetime, provider, selected microphone, or capture timeout change is proposed.

## Evidence

Successful USB recordings had raw callbacks and converted frames. Following USB
removal, built-in fallback was selected. The next logged attempt released Fn
about 0.1 seconds after capture startup, before any buffer arrived. The completion
path immediately reported zero bytes as a microphone failure, bypassing the
configured startup timeout. The screenshot warning persists until another attempt
or restart, so its display does not establish a continuing hardware stall.

MacBook was reachable over Tailscale SSH despite the .local hostname failing to
resolve from the Mini. Vox was stopped when inspected; its existing LaunchAgent
was restarted and microphone permission, hotkey startup, and built-in routing
passed. This is startup evidence only; real recording acceptance remains open.

## Current verification — 0.7.79/103

Both installed executables match SHA-256
`fe42741e3231f213e9f503e8b705a73d2e65653ca15ee05dbf9f763ec3d148e3`.
Signing requirements match the prior installed MacBook release. Startup confirms
microphone permission, Accessibility trust, hotkey setup, and built-in routing.
README and Help document short-release cancellation; timeout policy is unchanged.
`git diff --check` passes. This build is local and unreleased.

The user confirmed switching from the external keyboard to the MacBook's built-in
keyboard explained the missing Fn events. On 0.7.79/103, MacBook logs at 12:30 and
12:31 Pacific show two built-in fallback recordings: 3.878 s and 5.650 s, both with
raw callbacks, converted frames, STT, cleanup, and completed paste paths (3.678 s
and 3.352 s processing respectively). This verifies actual capture and pipeline
completion on the affected Mac; it is stronger than startup/route evidence.
No captured transcript content is included here. A sustained capture stall is not
established by this incident. Repeated USB disconnect/reconnect cycles and an
external-keyboard-compatible binding remain unverified; no binding was changed.

The documentation-only follow-up uses unique local identity 0.7.80/104 under the
project deployment rule. It contains the same capture logic as 0.7.79/103. Both Macs were installed/restarted; strict signatures and matching installed/package
SHA-256 `34a470335e8b0116d30e959872302dd6593e3735344e814354df50b915c2a545`
pass. Plist validation and diff whitespace pass; runtime tests were not repeated
for this documentation-only follow-up. No public release was requested.
