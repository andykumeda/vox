# Competitor capture and recovery evidence

Checked 2026-10-26. Owner: competitor-evidence workstream. State: Verified for the bounded static inspection below; runtime comparison remains Not started. No competitor was launched, microphone opened, account accessed, or recording uploaded. This report establishes design evidence, not comparative reliability or accuracy.

## Artifact identities

- Wispr Flow installed ASAR: `/Applications/Wispr Flow.app/Contents/Resources/app.asar`, SHA-256 `3a24fcfbfaee325b4abdac1ee54634b9006efa208ec329c623050899a7bab1f8`. Rehashed on this pass; exact match to the 1.5.339 artifact in [the existing inspection](wispr-flow-transcription-analysis.md). Reuse that bounded analysis instead of repeating it.
- Glaido installed version 0.0.16: `/Applications/Glaido.app/Contents/MacOS/glaido-core`, universal x86_64/arm64 Mach-O, SHA-256 `5a89ff06079da7c2b83598b5e62b8c5e17ca404cdbc4d84968388870edde513b`. REA selected arm64, container offset 33144832; UUID `F4923DD8-19C7-3299-BBA4-D439F0743B44`.

## Finding ledger

| Question | Evidence and conclusion | Coverage / remaining unknown |
| --- | --- | --- |
| Wispr capture readiness and recovery | Existing shipped-code analysis records a meeting first-frame watchdog (5 seconds), independent microphone/system clients, bounded reconnect, ping/pong deadlines, and a recorder worklet that flushes remaining samples | Partially answered. Meeting behavior must not be generalized to dictation; runtime activation and success rate untested |
| Wispr retries and preservation | Existing shipped-code analysis records retained packet/audio state, separate raw ASR/formatted text, and session UUID checks during retry | Partially answered. Client branches do not establish cloud provider routing, retention guarantees, or server implementation |
| Glaido capture health | Native artifact contains first-callback timing and callback-received diagnostics, a capture-watchdog cancellation reason, and callback-panic/persist-buffered-audio diagnostic | Partially answered: observed literal bytes only. Exact watchdog threshold, scheduling, recovery actions and reachable callers remain unknown |
| Glaido request recovery | Native artifact contains connection-loss/local-buffering, reconnect-limit, inactivity-timeout, missing-terminal-result, and post-end-audio hard-timeout diagnostics | Partially answered: observed literal bytes only. Does not establish retry policy, defaults, successful recovery, or actual server behavior |
| Glaido outcome handling/preservation | Native artifact contains explicit no-transcription failure, encrypted WAV validation, and persisted-buffered-audio diagnostics | Partially answered: observed literal bytes only. Does not establish encryption implementation, default retention, access controls, or complete failure coverage |
| Which is more reliable / accurate / faster? | No controlled benchmark was performed | Unresolved. Neither package inspection nor Vox unit tests establish parity or superiority |

## REA evidence and limitations

Wispr historical parent: `ev_3e0648f1860a0e5e66503abceab7041717557f8cb0fc5307b7cd71327c45c754`; summary `ev_bbd6909bfb1283a202363cbee7626c5b2fd8feb78f2914f74798a2b42b548836`; recorder-worklet view `ev_b25ad8e392db30065a84eb07e7047a8a8ccd262160dfbe70e0c33c680f476d1d`. These are historical references from the matching artifact report, not newly retrieved session records. Preserve that report's partial semantic coverage and native Jabra integrity contradiction; none of this pass executes that companion.

Glaido REA `inspect_macho` parent: `ev_0a14895236b942b83f1d5f5e2c2d6c69c31236d13cff48d8fee4517228b7c085`; summary `ev_dbfc7ba7c98902455fea985ac657c9a9d8cb02ae6936e2d30ebdea100510b21d`; dependencies view `ev_449c9b9b7e69f2c2d7d9b9e9df5eca1bd914cb137c6cf0c286583c965a0b54b1`. Native inventory observes CoreAudio, AudioToolbox and AudioUnit dependencies. It does not establish their call paths. Imports/exports are non-exhaustive for stripped/toolchain-hidden symbols. Evidence exported to `/private/tmp/vox-glaido-reliability-20261026.evidence.json` (not a repository artifact), then the session was closed. A provider-neutral snapshot was unavailable because native inventory has no concrete decompiler profile.

`search_procedures` returned `provider_unavailable`: Hopper launcher absent; Ghidra, IDA and Kuna unconfigured. No installation or registration changes were made. Decompilation and control-flow claims remain blocked on a suitable native analysis provider. Ordinary shell byte inspection below is explicitly separate from REA Evidence.

### Bounded Glaido literal observations

A Python byte search over the identified universal executable observed these exact ASCII/UTF-8 literal starts at decimal container offsets. These are diagnostic strings, not executed traces or recovered source. Negative keyword searches are not evidence of missing features.

| Container offset | Literal / diagnostic marker |
| --- | --- |
| 58842672 | `first_callback_ms`, followed by capture callback received diagnostic and `src/audio/capture.rs` anchors |
| 58923009 | `cancelled_capture_watchdog`, adjacent to distinct cancellation and no-speech outcomes |
| 58900408 | `buffering audio locally`, within connection-loss diagnostic |
| 58900836 | `buffering audio locally`, followed by reconnect-limit diagnostic |
| 58900585 | `no frames received within the inactivity window`, in WebSocket timeout diagnostic |
| 58837609 | `WAV file contains no audio data`, adjacent to WAV/header and audio decryption failures |

Additional nearby bytes name explicit no-transcription failure, callback panic with buffered-audio persistence, and deferred stream disposal after first IO callback. The source-path/line strings are compiler-emitted diagnostic anchors only; the corresponding source and control flow were not recovered.

## Minimal implications for Vox

1. Treat engine start, raw callback arrival, successful conversion, and successful disk writes as separate facts. A first usable frame is the readiness signal; silence is valid audio and must not trigger no-buffer recovery.
2. Bound missing-frame detection and recovery, surface the selected microphone and an actionable failure, and prevent old callbacks/timers from changing a newer recording. Avoid unbounded engine recreation: Vox already documents a prior AVAudioEngine teardown deadlock.
3. Distinguish capture failure, no speech, conversion/write failure, provider authentication/configuration failure, transient transport failure, and successful delivery. Preserve raw recognized text when cleanup fails. Retry transient errors only within configured limits and preserve explicit provider choice.
4. Keep current audio privacy behavior unless implementing an explicitly scoped opt-in encrypted recovery feature. Competitor retention strings do not authorize copying their retention policy.
5. Verify with fault injection plus repeated real USB/built-in recordings, post-idle/post-meeting runs, unplug/reconnect, network interruption, and paste checks. Measure lost recordings, false silence rejection, time to first usable frame, delivery latency, recognition error and stale insertion against the same consented speech set. Do not claim competitor parity before that comparison.

No runtime benchmark, competitor account flow, proprietary cloud implementation, or Glaido decompilation was checked. These limits do not block fixing source-confirmed Vox failures.
