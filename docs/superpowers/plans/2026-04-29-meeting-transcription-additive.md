# Meeting Transcription (Additive) — Execution Plan (2026-04-29)

## Objective
Add meeting transcription as a **new feature path** while preserving Vox's existing dictation/STT workflow as the primary use-case.

## Locked Decisions (from stakeholder)
1. Capture source for Meeting Mode: **system/call audio only**.
2. Output UX: **in-app transcript list + export**.
3. First release diarization: **deferred (no speaker labels required)**.
4. Consent UX: **one-time acknowledgment** before first meeting capture.
5. Priority: **accurate/complete transcript capture** over summarization.
6. Transcript storage default: **Application Support (app-managed)**.
7. Hard requirement: Meeting features must **not degrade existing dictation STT quality/latency/reliability**.

## Non-goals for v1
- No diarization in v1.
- No meeting summarization requirement in v1.
- No replacement of existing dictation controls/hotkeys.

---

## Milestone M1 — Additive foundation (no behavior change to existing users)

### Deliverables
- Meeting Mode settings section (off by default)
- One-time consent gate
- System-audio backend preflight checks
- Separate menu commands for meeting session lifecycle

### Tasks
- [x] Add meeting settings keys in `Sources/vox/Util/AppSettings.swift`:
  - [x] `meetingModeEnabled: Bool = false`
  - [x] `meetingConsentAcknowledged: Bool = false`
  - [x] `meetingCaptureBackend` (system-audio options only)
- [x] Add `Meeting Transcription (Beta)` section in `Sources/vox/App/SettingsWindow.swift`:
  - [x] enable toggle
  - [x] consent UI
  - [x] system-audio availability status
- [ ] Refactor `Sources/vox/Audio/AudioRecorder.swift` to support backend abstraction while keeping current microphone dictation backend untouched. **Deferred to M2 — refactor is unjustified until a real second backend exists; touching the dictation recorder now violates the no-regression rule.**
- [x] Add availability diagnostics and typed errors for meeting preflight (`Sources/vox/Meeting/MeetingPreflight.swift`).
- [x] Add `Start Meeting Transcript` / `Stop Meeting Transcript` menu actions in `Sources/vox/App/MenuBarController.swift` (gated by `meetingModeEnabled`).
- [x] Enforce meeting start gate checks (mode enabled, consent, API key, backend ready) — see `MeetingPreflight.gate(...)`.
- [x] Add regression tests proving dictation path behavior unchanged when Meeting Mode is off — `DictationRegressionTests` 221-test run, failure_rate=0.0, quality=1.0; `MeetingSettingsTests` confirms meeting reads do not perturb dictation toggles.

### Acceptance criteria
- Existing dictation UX and STT behavior remain unchanged by default.
- Meeting actions are independently accessible and fail gracefully with actionable errors.

---

## Milestone M2 — Meeting pipeline + timestamped transcripts

### Deliverables
- Long-running chunked transcription session
- Transcript persistence
- In-app transcript list + export

### Tasks
- [ ] Create `Sources/vox/STT/MeetingTranscriptionSession.swift` with ordered chunk queue, retry/backoff, cancellation/finalization.
- [ ] Extend `Sources/vox/STT/OpenAITranscriber.swift` with chunk-oriented meeting methods (without altering dictation methods).
- [ ] Add transcript models/store in `Sources/vox/Util/`:
  - [ ] `TranscriptSession`
  - [ ] `TranscriptSegment` (`startTime`, `endTime`, `text`)
  - [ ] storage in Application Support
- [ ] Add transcript list UI and export actions (plain + timestamped text) in `Sources/vox/App/`.
- [ ] Add tests for ordering, retry behavior, persistence integrity, and export format.

### Acceptance criteria
- User can complete a meeting session and review/export timestamped transcript.
- Meeting pipeline failures do not break dictation flow.

---

## Milestone M3 — Hardening for reliability and primary-use-case protection

### Deliverables
- Non-regression gates for dictation STT
- Resource isolation between meeting and dictation paths
- Structured diagnostics for transcript completeness

### Tasks
- [ ] Create dictation baseline + regression suite in `Tests/voxTests/` (latency/failure/output fixtures).
- [ ] Add merge-blocking thresholds for dictation regressions.
- [ ] Isolate execution resources so meeting workloads cannot starve dictation requests.
- [ ] Add meeting telemetry with redaction under `Sources/vox/Util/`.
- [ ] Add gap annotations/checkpoints for partial chunk failures.
- [ ] Update help docs with consent + meeting-capture troubleshooting.

### Acceptance criteria
- Dictation STT remains within baseline quality/latency/reliability bounds.
- Meeting interruptions are visible and recoverable without app-wide failure.

---

## Decision Escalation Rules (raise to stakeholder)
Raise immediately if any of the following require a choice:
- System-audio capture implementation requires third-party driver dependency vs native-only approach tradeoff.
- Meeting and dictation contend for shared API quota/throughput, requiring explicit prioritization policy.
- Export format/UI scope expansion beyond plain/timestamped text.
- Any proposal that changes existing dictation defaults, prompts, models, or hotkeys.

## Handoff Checklist for Future Sessions
- [ ] Confirm all locked decisions still stand.
- [ ] Record milestone status by task checkbox updates in this plan.
- [ ] Update `HANDOFF.md` with concrete "done vs remaining" and commit SHA references.
- [ ] Note any new decisions required under "Decision Escalation".
