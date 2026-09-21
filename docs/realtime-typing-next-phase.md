# Real-Time Inline Typing: Next Phase

Status: planned; not implemented.

This document defines the next dictation phase for Vox: show provisional words
at the actual cursor while recording, then replace only those words with Vox's
normal final result. It is intentionally narrower than universal live typing.
The planned first implementation will be available only in local editors where Vox can
prove ownership of an editable Accessibility range for the entire transaction.

## Architecture

Use a hybrid pipeline so live display cannot weaken the current final-output
contract:

1. At recording start, resolve and lock the frontmost process, focused editable
   Accessibility element, selection, cursor position, and surrounding-text
   fingerprint.
2. Tee the recorder's existing 16 kHz PCM to both the temporary WAV and an
   OpenAI realtime transcription session.
3. Accumulate ordered realtime transcript deltas. At a coalesced cadence of
   roughly 100-250 ms, replace the entire verified provisional range with the
   accumulated preview rather than appending individual deltas.
4. When recording stops, close the realtime session but keep the existing WAV
   transcription authoritative. Run the completed-file transcript through the
   current post-processing and Smart Cleanup pipeline.
5. Reverify ownership and replace only Vox's provisional range with the final
   text. Preserve the existing suffix-key behavior and transcript-history path.

Realtime output is preview data only. The initial phase does not replace the
completed-file transcription, silence guards, post-processing, Smart Cleanup,
or established record-then-paste path.

Before implementation, select a supported realtime transcription model and
validate the exact session protocol against current official OpenAI documentation.
The earlier `gpt-live-transcribe` proposal is a design candidate, not a shipped
dependency or a promise of current model availability. Record the event
ordering, delta accumulation rules, stop/flush behavior, error events, and
whether an authoritative completion event exists. Do not infer a final
transcript contract from partial deltas. Start with the [official OpenAI
documentation](https://developers.openai.com/api/docs/) and the current realtime
transcription reference when this phase is authorized.

## Provisional-Range Transaction

Treat inline typing as an ownership transaction with these captured fields:

- target process identifier and bundle identifier;
- focused Accessibility element identity and editability state;
- original selected range and selected text, including an empty selection;
- current Vox provisional range and exact provisional text;
- expected selection/cursor after the provisional range;
- bounded surrounding-text fingerprint before and after the range.

Before every provisional or final replacement, verify all captured invariants
that the target exposes. A write is permitted only when the process, element,
range contents, selection, and surrounding fingerprint still match the prior
Vox write. Secure fields are always ineligible. Any missing capability needed
to prove ownership makes the target ineligible before the first inline write.

The transaction has four terminal outcomes:

- **Committed:** ownership remains valid and the verified provisional range is
  replaced once with the final processed transcript.
- **Detached:** focus, selection, surrounding text, element identity, or range
  contents change after preview text has appeared. Vox stops all inline writes,
  leaves existing text untouched, places the final transcript on the clipboard,
  and notifies the user. It never pastes the final text into a new target.
- **Fallback:** realtime setup fails before any provisional write. Vox continues
  through today's completed-file transcription and record-then-paste path.
- **Cancelled/empty:** if Vox has inserted provisional text, it restores the
  original selection only while complete ownership is still provable. Otherwise
  it detaches and leaves the editor untouched.

A realtime failure after the first provisional write is a detached outcome,
not a paste fallback. This prevents duplicate text and prevents Vox from
overwriting user edits. A failure after recording release still allows the
completed WAV pipeline to produce a clipboard result.

## Eligibility and Fallbacks

Ship the first phase behind an explicit feature flag and a fail-closed
allowlist. Start with native AppKit text controls that expose stable focused
element, selected-text range, range replacement, and readable surrounding text.
Add an application or editor class only after its complete acceptance row
passes; do not treat one successful text field as coverage for an entire app.

Browser content-editables, Electron editors, Notes, custom editors, and other
complex controls remain unsupported until individually proven. Password and
secure-entry fields are permanently excluded. Terminals, Screen Sharing/VNC,
RustDesk, Parsec, and Remote Control Mode keep their current specialized
record-then-paste paths. Unsupported local editors may use a floating live
preview later, but the fallback for this phase is existing Vox behavior.

## Privacy and Data Lifecycle

- Stream only audio needed for the active dictation session to the configured
  OpenAI service; do not start a realtime session during idle time.
- Keep the temporary WAV solely for the authoritative existing transcription
  path and delete terminal audio according to the current recording lifecycle.
- Treat provisional and final transcripts as sensitive. Persist transcript
  history only through Vox's existing encrypted storage; do not add plaintext
  realtime logs, delta archives, crash attachments, or analytics payloads.
- Keep normal diagnostics content-free: log state transitions, eligibility,
  timings, and failure categories without audio or transcript text.
- Closing, cancelling, detaching, quitting, or losing the network must close the
  realtime session and release buffered PCM.

## Acceptance Matrix

Each supported editor must pass the applicable desktop matrix with literal
dictation and with Smart Cleanup enabled and disabled.

| Scenario | Required result |
| --- | --- |
| Empty cursor in an allowlisted native field | Provisional words appear at the locked cursor; final processing replaces exactly that range once. |
| Existing selection | Preview replaces only the captured selection; a successful final commit replaces only Vox's provisional range. |
| Delta revisions and punctuation changes | Accumulated preview replaces the full owned range without duplication, reordering, or stray suffixes. |
| User moves focus or selection | Inline updates stop immediately; final text goes to the clipboard with a visible detached notification. |
| User edits inside or adjacent to preview | Ownership check fails before the next write; user text is preserved and the transaction detaches. |
| Target closes, becomes read-only, or loses Accessibility access | Vox performs no further editor writes and preserves the final result on the clipboard. |
| Realtime connection fails before first write | Current completed-file transcription and paste behavior completes without duplicate output. |
| Realtime connection fails after first write | Existing provisional text is left untouched; final output is clipboard-only. |
| Empty, silent, or cancelled recording | Original selection is restored only when full ownership is still verified; otherwise the editor is untouched. |
| Secure field | Inline typing and transcript insertion are refused. |
| Terminal or remote-desktop target | Existing target-specific record-then-paste behavior is used; no Accessibility provisional range is created. |
| Rapid consecutive dictations | Each recording owns an independent target transaction; an older completion cannot overwrite a newer range or UI state. |
| App quit or crash recovery | No PCM or plaintext delta artifact remains; no stale transaction writes after relaunch. |

Automated tests must cover the transaction state machine, accumulated-delta
replacement, eligibility decisions, ownership invalidation, fallback timing,
cancel/empty restoration, and independent concurrent pipelines. Manual testing
must cover every allowlisted editor plus at least one rejected browser editor,
one terminal, Screen Sharing, RustDesk, and the pinned-microphone disconnect
path. Accessibility behavior, cursor integrity, undo behavior, and remote-client
insertion remain live gates that unit tests cannot satisfy.

## Rollout and Rollback

Begin with the feature flag off. Enable it only for the verified allowlist and
retain the current path as the default everywhere else. Roll out one editor
class at a time, recording the exact app/version and control type that passed.
Measure only content-free outcomes such as eligible, committed, detached,
fallback, and failed.

Disable the feature flag if any test or live report shows lost user text,
duplicate final text, insertion into a different target, insecure-field access,
or retained terminal audio. Rollback means returning all dictations to the
existing record-then-paste path; it must not attempt to repair or remove text
from completed or detached transactions.
