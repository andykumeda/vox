# Vox reliability stabilization — 2026-10-26

Scope: recurring empty dictation, silent capture/conversion failures, meeting data loss,
provider transport retry correctness, and shipped competitor evidence. Unrelated
streaming, retained audio, correction learning and app-aware formatting remain deferred.
No claim of Wispr/Glaido parity without a controlled live comparison.

| Workstream / owner | State | Acceptance / files | Verification / remaining |
| --- | --- | --- | --- |
| Capture readiness / primary | Deployed | AudioRecorder, MenuBarController, service configuration: observed frames before recording state; no-frame/stalled/conversion/write failure distinct from silence; safe restart action | Fake engine and health/state/config tests; USB/post-meeting live smoke pending |
| Provider and source preservation / provider agent | Deployed | OpenRouterMeetingTranscriber, MeetingTranscriptionSession: configured transport retry, preserve valid sources and disclose partial capture | Injected transport and source-failure tests |
| Continuous meeting mic / meeting agent | Deployed | MeetingMicCapture: no quiet-triggered destructive restart; explicit errors | 3 focused tests passed; long quiet real meeting pending |
| Speech false rejection / meeting agent | Deployed | Shared hallucination guard: preserve real polite phrases while retaining silence protection | Focused gate tests and dictation fixtures |
| Competitor evidence / REA agent | Verified | competitor-reliability-evidence.md: identity-bound static evidence and explicit limitations | Wispr artifact matches previous evidence; Glaido native inventory/strings only; decompiler unavailable |
| Integration and local production / primary | Deployed | Unique version/build, full tests, regression fixtures, signed install/restart, focused commit | Live USB/meeting/network and comparative benchmark remain required |

Observed incident: Mini 0.7.77/101 recorded 11 seconds on AT2020USB-X at 18:19 Pacific,
produced only a 44-byte WAV header, then silently skipped transcription. Restart restored
capture at 18:23. Old first-buffer logging occurred after conversion, so it could not
identify absent callbacks versus converter failures. No original audio existed to recover.

Capture recovery deliberately uses an explicit app restart only when no dictation or
meeting work is active. Rebuilding AVAudioEngine during capture previously deadlocked;
changing engine lifetime speculatively would not establish a durable fix. Missing-frame
checks use monotonic time and count quiet buffers as healthy. Audio remains ephemeral.

## Verification and delivery

- `swift test`: 525 macOS + 21 VoxCore tests, zero failures. Initial integration
  run caught the new provider-body privacy assertions before their fix; final run passes.
- `./scripts/run-dictation-regression.sh`: seven fixtures, quality 1.0, failure rate 0.0.
- `./scripts/build-app.sh`: installed signed 0.7.78 / 102 on Mini; strict deep
  verification passes and installed/packaged binary SHA-256 matches
  `2fc197ba2e4885ebec9a2c345db0101a1aef686f554c1ada40cd74783dda807e`.
- LaunchAgent restarted with microphone permission, hotkey and Accessibility passing.
  User confirmed successful dictation insertion at 18:37 Pacific; logs show first raw
  callback, converted frames, 1.94 seconds of audio and completion in 4.318 seconds.
- Public Sparkle publication authorized; packaging/signing/public verification in progress.

## Remaining acceptance checks

Repeated USB/built-in input after long idle and meetings, disconnect/reconnect,
actual source failure mid-meeting, provider network interruption, restart menu UI,
MacBook Sparkle installation, and controlled competitor benchmark remain unverified.
The original capture stall's hardware/framework trigger is not established. Synchronous
framework hangs cannot be rescued by a main-runloop health timer. Failed audio is
still ephemeral, and broader live meeting health/streaming and opt-in encrypted retry
are not implemented here. Short/quiet speech thresholds remain unchanged pending
labeled audio calibration; the polite-phrase false rejection was fixed separately.

Release candidate DMG verified read-only: 0.7.78 / 102, 2,775,141 bytes,
SHA-256 `e0ec90c493813e63be7a834f7ef6309f82e842d40163d39db74fdbaddf7e37e2`.
Sparkle Ed25519 verifies against the mounted app's public key. Packaged and installed
Mach-O UUID `75A42440-67C2-3834-947F-58ACB515B206` and designated requirements match;
re-signing during DMG packaging changes executable signature bytes, not the code UUID.
