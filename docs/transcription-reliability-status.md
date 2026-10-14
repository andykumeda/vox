# Transcription reliability and OpenRouter meetings

Updated: 2026-10-14. Owner: root integration; OpenRouter backend workstream.

| Workstream | State | Acceptance / evidence | Remaining checks |
| --- | --- | --- | --- |
| Spoken digit sequences | Deployed | Formatter and real pipeline regression reproduced “Testing one two three.” → “Testing 6.”; preserve distinct digits, compound quantities, units and spacing | Spoken MacBook smoke pending |
| OpenRouter meeting audio | Deployed | Explicit provider/key/model; timestamped chunks; no provider fallback; optional speaker labels scoped per chunk | Mock request/session/full checks pass; real meeting pending |
| Intermittent Fn capture | In progress | MacBook recordings included 44-byte header-only WAVs; later recordings captured audio. Safe app restart completed with no audio files open. Permissions/hotkey startup pass | Post-restart spoken verification; determine capture stall cause before changing engine lifecycle |
| Short-clip speech gate | In progress | Captured 1.3–1.8s clips had 0.52–0.56s total voiced audio but 0.20–0.24s longest voiced run; gate requires 0.28s. Other clips reach OpenRouter HTTP 200 | Original audio is ephemeral; no claim that rejected clips contain speech. Controlled repeated short-speech and quiet-room verification before changing protection |

## Configuration

OpenRouter meetings use the saved `openrouter-api-key`. Select OpenRouter explicitly
under Meeting Transcription; dictation selection alone does not change meeting audio.
`openrouterMeetingModel`, JSON `openrouterMeetingProviderOptions`, and
`openrouterMeetingUSDPerHour` use environment > saved settings > bundled defaults.
Speaker identities from separate chunks must not be described as one stable person.

## Deployment

Installed unreleased 0.7.76 / 100 on Mini and MacBook; strict deep signatures pass,
both binaries match SHA-256 `27c94e95cb2999037a52b61b4bf5c3db36d6149b746f784b11e65141c44c5dca`.
MacBook LaunchAgent restarted with OpenRouter meeting provider explicitly saved.
Mini LaunchAgent was not loaded; installed app was opened directly and hotkey,
Microphone permission and Accessibility startup passed. MacBook prior app is
retained under `/tmp/vox-deploy-100-01a13bd2/Vox.previous.app`.

`swift test`: 505 macOS + 19 VoxCore tests pass. Dictation regression: seven
fixtures, quality 1.0, failure rate 0.0. `git diff --check` passes.
Spoken digit/live meeting and repeated short-speech/quiet-room checks remain pending.
Public Sparkle remains 0.7.75 / 99 until a release is explicitly authorized.
No original dictation or meeting audio is retained for replay after terminal processing.
