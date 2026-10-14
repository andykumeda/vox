# Wispr Flow transcription implementation: bounded inspection

Checked 2026-10-14. Installed macOS app: Wispr Flow 1.5.339.
Scope: read-only packaged JavaScript and public documentation; no account access,
request replay, microphone execution, or server-side source access.

## Findings

| Question | Observed evidence | Meaning / limits |
| --- | --- | --- |
| Capture | Shipped `recorderWorklet.js` uses an AudioWorklet processor, 640-sample buffers, start/stop messages, per-input buffers, and flushes remaining samples before sending its done message | Audio is captured and handed off in chunks; static evidence does not show the sample rate of every runtime |
| Audio detection | Main bundle's level scaler tracks a floor; audio-boundary helper uses floor + 3 dB, takes first and last above-threshold packet, and retains two packets of padding on either side | Detection uses an audio envelope rather than merely requiring a contiguous voiced run. Exact runtime paths and every rejection rule remain unknown |
| Failure handling | Dictation code retains packet/audio state, stores raw ASR and formatted text separately, checks session UUID during retry, and implements transcription fallback paths | Their cloud service owns recognition/formatting; provider identities and production routing are not established by these client branches |
| Meetings | Main bundle implements a WebSocket route `meeting/transcribe`, separate mic/system clients, pending audio buffers, interim/final token state, first-frame watchdog (5s), ping (30s)/pong deadline (10s), and bounded reconnect attempts | Streaming and per-source health are explicit in the client. Runtime activation and server implementation were not tested |
| Number sequences | Public formatting guide treats spoken numbering/sequence words as structure. Research page describes trained formatting models separately from ASR | No server-side parser or prompt is shipped here. Exact result for “testing one two three” was not tested in Wispr and must not be claimed |

## Sources and evidence

- Installed artifact: `/Applications/Wispr Flow.app/Contents/Resources/app.asar`.
  SHA-256: `3a24fcfbfaee325b4abdac1ee54634b9006efa208ec329c623050899a7bab1f8`.
- REA parent: `ev_3e0648f1860a0e5e66503abceab7041717557f8cb0fc5307b7cd71327c45c754`.
  Summary: `ev_bbd6909bfb1283a202363cbee7626c5b2fd8feb78f2914f74798a2b42b548836`.
- Recorder worklet view: `ev_b25ad8e392db30065a84eb07e7047a8a8ccd262160dfbe70e0c33c680f476d1d`.
  Internal path `.webpack/renderer/dist/recorderWorklet.js`, 1650 bytes,
  SHA-256 `3cd6c33bc2fcb35337fd1a43896fb92aa89ec3066a9d978fc02d8a5292d18d2e`.
- Main bundle static text inspection: level scaler near character 2927949;
  audio bounds near 3400669; dictation chunk fallback near 3101912;
  meeting client identified by `meeting/transcribe`, `firstFrameWatchdog`,
  `startKeepalive`, and `shouldAttemptReconnect`. These locations are decoded
  bundle character offsets, not native addresses or observed runtime traces.
- [Language-specific ASR and formatting research](https://wisprflow.ai/research/supporting-languages).
- [Smart Formatting and Backtrack](https://docs.wisprflow.ai/articles/5373093536-how-do-i-use-smart-formatting-and-backtrack).
- [Microphone troubleshooting](https://docs.wisprflow.ai/articles/4351452717-troubleshooting-mic-issues).
- [Meeting audio troubleshooting](https://docs.wisprflow.ai/articles/3089221553-troubleshooting-notetaker-recording-and-audio-beta).

## Coverage and unknowns

REA parsed 25 JavaScript files and inventoried 39 relevant files. Its semantic
analysis is partial due to worker heap/result limits. A native Jabra companion's
bytes differ from the ASAR integrity declaration; analysis explicitly continued
with that contradiction recorded, without claiming why it differs. No findings
here depend on executing that companion. A graph trace for `meeting/transcribe`
returned no match because graph coverage is partial; direct shipped text contains
that route, and the negative graph result is not evidence of feature absence.
No native analysis session was opened.

## Vox implications

The reproduced “one two three” → `6` bug is Vox's additive number normalizer,
not evidence of incorrect ASR. Preserve the sequence before cleanup.
Separately, expose audio startup/health and distinguish a missing first buffer,
quiet capture, rejected short speech, authentication, and request failures.
A microphone failure cannot be repaired by switching transcription models.
Wispr's cloud fallback design does not authorize Vox to silently switch providers;
Vox keeps explicit provider selection and fails closed.
