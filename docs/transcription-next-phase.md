# Next phase: transcription reliability and usability

Recorded: 2026-10-14. Implementation status: **Not started**.

These items are planned for the next phase. This document does not implement them
or claim they have been verified. Priorities are based on the Vox/Wispr Flow
comparison, current Vox source and observed MacBook failures. Wispr's packaged
client was inspected statically; its server internals and comparative accuracy
remain unverified. See [inspection evidence](wispr-flow-transcription-analysis.md).

## Task ledger

Owner for all items: next-phase Vox maintainer. Assign implementation owners when
the phase begins. Every item starts **Not started** and advances through
**In progress**, **Blocked**, **Verified**, and **Deployed** only with evidence.

| ID | Priority | State | Item | Scope / acceptance criteria | Verification | Dependencies |
| --- | --- | --- | --- | --- | --- | --- |
| NP-01 | First | Not started | Normalize provider failures and repair OpenRouter meeting retries | Use shared typed transport/HTTP/configuration outcomes; retry temporary connection failures within the configured budget; fail promptly on invalid credentials, unsupported models and invalid responses; never change providers implicitly | Inject timeout/disconnect then success, exhausted budget, cancellation, 401 and unsupported-model responses; real interrupted-network meeting | Shared failure contract owned before NP-03 integration |
| NP-02 | First | Not started | Microphone readiness and actionable feedback | Show Starting, Receiving audio and Processing; require observed buffers before claiming audio is flowing; detect missing first buffer; name the active input and offer the appropriate recovery; preserve early samples | Fake engine with delayed/absent first buffer; live built-in/USB microphone, disconnect/reconnect, and post-meeting Fn tests | Coordinate capture event contract with NP-03 |
| NP-03 | First | Not started | Unify dictation processing | Route macOS and shared-core processing through one policy; preserve command/prose, verbatim, dictionary, cleanup and suffix behavior; distinguish no buffers, insufficient speech, provider failure and success | Pipeline tests plus existing dictation fixtures; compare acceptance and output across both call sites; live paste smoke | NP-01 failure contract; NP-02 capture metadata |
| NP-04 | First | Not started | Improve short/quiet speech detection | Evaluate adaptive noise calibration and speech detection; preserve short real speech without admitting clicks, handling noise or silent-room hallucinations; retain appropriate audio padding | Consent-based labeled samples covering short phrases, whispered/far-field speech, room noise and clicks; compare false rejection/acceptance against current gate before replacing it | NP-03 unified policy; NP-02 capture diagnostics |
| NP-05 | First | Not started | Per-source meeting health | Show independent microphone, computer-audio and Phone/FaceTime health; immediately disclose partial capture; distinguish missing buffers from quiet audio before recovery; avoid repeated resets during legitimate silence | Simulated source startup/stall/failure; live meeting-app and route-change checks for each source; verify unaffected sources continue | NP-02 event pattern; existing meeting recorder boundaries |
| NP-06 | Follow-on | Not started | Incremental/live meeting transcription | Process completed chunks during capture or use provider-supported streaming; show backlog, connection and retry states; preserve timestamps and avoid claiming stable speaker identity across independent chunks | Interrupted/reconnected sessions, long meetings, cancellation, duplicate/out-of-order responses, timeline and speaker-scope checks; real provider recording | NP-01 and NP-05; explicit provider capabilities and session/chunk contract |
| NP-07 | Follow-on | Not started | Optional recovery of failed audio | Add opt-in encrypted retention of failed audio with expiry, Retry and Delete; retain ephemeral behavior by default; session IDs prevent stale retry results from entering new dictations | Encryption, expiry, deletion and migration tests; interrupted retry/new dictation; live restart recovery | NP-01/NP-03 outcomes; explicit retention and encryption lifecycle design |
| NP-08 | Follow-on | Not started | Cleanup controls and raw-text recovery | Add Copy raw, Copy final and Reformat; distinguish raw transcription from formatting-only behavior; preserve wording by default; retain original text after failure | Cleanup/dictionary/number/command fixtures; history actions and clipboard smoke; ensure retries do not overwrite originals | NP-03 result contract; existing encrypted raw/final history |
| NP-09 | Follow-on | Not started | Dictionary correction learning | First offer Add correction from history; later suggest likely recognition corrections for user approval; exclude code, paths, IDs, numbers and unrelated sentence rewrites | Positive/negative correction pairs, repeated edits, dictionary persistence and explicit user-control tests | NP-08 history actions; optional edit observation needs separate design |
| NP-10 | Later | Not started | App-aware formatting | Add explicit messaging, email, document and terminal styles; start with app identity; surrounding-text access is separately opt-in with clear provider disclosure | Per-app style fixtures, focus changes and terminal preservation; verify surrounding text is neither collected nor sent when disabled | NP-03 and NP-08; user-approved context boundaries |
| NP-11 | Later | Not started | Recognition model benchmarks | Compare available configured models on short speech, digits, names, commands, quiet speech and realistic noise; use measured accuracy, latency and cost to inform defaults | Human reference transcripts, recognition error and number/name preservation, end-to-end latency and failure rate; record model/provider/date | NP-04 labeled sample design; explicit consent for retained benchmark audio |

## Ordering and implementation boundaries

1. Start with NP-01 and NP-02. Agree typed outcomes and capture metadata before
   NP-03; these touch shared processing and must have coordinated ownership.
2. Build NP-04 and NP-05 on the stable event/result contracts. Do not weaken the
   current silence gate based only on RMS or aggregate voiced duration.
3. Address NP-06 through NP-09 after reliability work. Keep independently
   reviewable increments; do not combine retention, live streaming and cleanup
   into one broad change.
4. NP-10 and NP-11 follow separately. Wispr's Canto is proprietary; its claimed
   performance is not proof of better results for Vox or authorization to train
   on personal recordings. Recreating its training infrastructure is outside scope.

Provider endpoints, model IDs, budgets, retry policies and defaults stay in the
shared configuration path. Keep credentials in Keychain and diagnostic logs free
of audio, transcript bodies and credentials. Do not introduce silent provider
fallback. Audio retention remains opt-in, encrypted and bounded by expiry.

Preserve already-deferred [real-time inline typing](realtime-typing-next-phase.md)
as a separate item; live meeting transcripts do not authorize that work.

## Evidence and current state

- NP-01 is a source-confirmed gap: `OpenRouterMeetingTranscriber` directly throws
  URLSession transport errors, while `MeetingTranscriptionSession.transcribeWithRetry`
  catches only `TranscriptionError.transportError`.
- MacBook failures included header-only WAVs and short recordings rejected by
  the current sustained-run gate. The original audio was deleted; these metrics
  do not prove every rejected clip contained speech.
- The digit-sequence normalizer fix is already deployed in 0.7.76 / 100.
  The user confirmed a live MacBook result of **Testing 1 2 3.** on 2026-10-14.
  It is completed work, not a next-phase implementation item.
- OpenRouter meetings are implemented/deployed, but real meeting/provider upload
  verification remains pending. The retry improvement above is separate work.
- Current-state ledger: [transcription reliability](transcription-reliability-status.md).

## Release and completion gates

For each implemented item, record files, focused tests, actual live results,
commit and deployment reference in this ledger/current-state docs. Follow
repository requirements for unique bundle version/build, local production
installation and signed publication only when authorized. Pending physical/OS
smoke must remain explicit and must not be reported as verified.
