# P1 — MacBook USB-to-built-in capture failure

Reported 2026-10-27. Owner: Codex. Overall state: In progress.
Priority: P1, ahead of deferred transcription features. Keep open until live
MacBook capture across USB disconnect/reconnect is verified. Correct route labels
and successful app restarts alone do not satisfy acceptance.

| Work | State | Acceptance / scope | Verification |
| --- | --- | --- | --- |
| Capture incident diagnosis | In progress | Distinguish short release, no callbacks, converter failure, and hotkey release | MacBook 0.7.78/102 logs: USB delivered frames; fallback selected; next attempt stopped about 0.1 s after start with no callback |
| Early-release classification | Verified | AudioRecorder and MenuBarController: empty release during Starting cancels; timeout, conversion and save errors remain failures | Original regression failed with the screenshot error; 526 macOS + 21 VoxCore tests pass; seven dictation fixtures quality 1.0/failure rate 0.0 |
| Local production deployment | Deployed | Unique unreleased 0.7.79/103 signed install/restart on Mini and MacBook | Mini and MacBook installed/restarted; strict signatures pass, executable SHA-256 matches; public Sparkle stays 0.7.78/102; no push/publication requested |
| Actual microphone-switch validation | Not started | Hold Fn for 3–5 s and dictate on built-in after USB disconnect, repeat; reconnect USB and repeat; verify raw and converted frames plus transcription | User test requested; sustained capture stall not established by current trace |

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

The user reports that a subsequent 3–5 second Fn hold still does not work and
shows no message. The reopened 0.7.78 app logged no new Fn press, so that attempt
did not reach capture. An OS event-tap inventory showed its listener enabled;
a process sample showed the main run loop idle rather than blocked. Do not
claim the microphone switch is resolved. Keyboard type and local/remote event
path clarification is pending, followed by a new 0.7.79 live test. Track hotkey
delivery separately from a confirmed capture stall; neither startup nor the
early-release regression establishes successful built-in dictation.
