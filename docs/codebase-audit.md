# Codebase audit — 2026-09-20

Scope: all tracked macOS and iOS implementation, shared VoxCore, tests, build
scripts, package/project configuration, repository documentation, bundled Help,
and the public landing-page source. Generated build outputs, local benchmarks,
credentials, and historical release artifacts are outside the cleanup scope.

The repository started clean on `main` at `1fee68d`. Removal requires evidence
that code is unreachable, has no remaining consumer, or only supports obsolete
behavior. Active regression tests, persisted-data migrations, OS callbacks,
and the deferred iOS/realtime work remain protected.

| Workstream | Owner | State | Acceptance and verification |
| --- | --- | --- | --- |
| macOS application and tests | macOS review agent | Verified | Inspect all macOS modules and tests; remove proven dead paths and obsolete tests; preserve OS integration behavior; full Swift suite and installed-app check. |
| VoxCore and iOS | shared/mobile review agent | Verified | Inspect shared pipeline, mobile state machine, keyboard, intents, and tests; preserve public/mobile consumers; full Swift suite and generic iOS build. |
| Repository and end-user docs | documentation review agent | Verified | README, bundled Help, Mobile README, operational docs, deferred designs, and landing page checked against implementation; local links and rendered Help verified. |
| Tooling and integration | primary agent | Deployed | Manifests, scripts, CI, signing resources, and handoff reviewed; checks passed; unique unreleased build installed, restarted, and inspected. |

Allowed states: `Not started`, `In progress`, `Blocked`, `Verified`, `Deployed`.

## Evidence and disposition

- Baseline `swift test`: 479 macOS + 12 VoxCore tests passed.
- Integrated `swift test`: 458 macOS + 12 VoxCore tests passed. Removed 24
  obsolete/duplicate test methods, added three meaningful regressions, and
  repaired three existing cleanup tests that previously bypassed the branch
  named by the test. No active test target was disabled.
- `./scripts/run-dictation-regression.sh`: seven fixtures, quality `1.0`,
  failure rate `0.0`, local fixture runtime 6.14 ms. This is not an end-to-end
  microphone or provider benchmark.
- Generic iOS Debug build passed on Xcode 27.0 (`27A5209h`) with
  `CODE_SIGNING_ALLOWED=NO`, including the final shared-code crash fixes.
- All six shell scripts pass `bash -n`; all six tracked plist/entitlement
  files parse; local Markdown/HTML document links resolve.
- Separate macOS and shared/mobile reviewers cross-reviewed one another's
  changes and found no integration blockers. The existing Sendable capture
  warning and async test-lock warnings remain; this is a Swift 5 language-mode
  package, not a completed Swift 6 concurrency migration.
- Public Sparkle remains `0.7.59` / `83`. The cleanup is installed and running
  locally as unreleased `0.7.61` / `85`; its executable and bundled Help match
  the built app, strict code-signature verification passes, Accessibility and
  Microphone startup checks pass, and the main window and Help render correctly.
  Public Sparkle publication is a separate action and is not part of this request.

## Changes and removal evidence

- Removed `MeetingAudioMixer.swift`: no caller; current Deepgram processing
  transcribes separate streams. Removed the disconnected standalone Help and
  Settings controllers, old menu selectors/icon renderers, and sidebar
  placeholder; actual AppKit selectors and the main-window destinations remain.
- Removed the uncalled synchronous `TextInjector.paste` implementation and its
  private sync-only fallback/wait tree. All live `pasteAsync` target branches
  and fallback order remain. Removed an unused Caps Lock experiment and six
  policy helpers whose only consumers were their own tests; those helpers did
  not control production insertion. Actual target/focus/keystroke regressions
  remain.
- Removed orphan WAV repair that ran immediately before the startup deletion
  sweep, unused meeting retranscription and age-based audio purge APIs, and
  the write-only audio-retention provider. Kept encrypted migrations, Codable
  compatibility metadata, terminal deletion, startup privacy sweeps, and their
  tests. Removed `RecordingArchiveTests.swift`, which tested only the deleted
  repair routine.
- Removed `MeetingMutexTests.swift`, which only asserted closures assigned in
  each test. Replaced the mutable injection hook with the same production
  meeting-recording condition. Removed write-only hotkey/dictionary watcher
  state, unused detector callbacks/test scaffolding, an uncalled history purge,
  duplicate sound defaults, and an unused certificate-script variable.
- Removed unreachable newline placeholder swapping after CleanupProcessor's
  earlier newline bypass, duplicate percent-unit entries, and number-token
  metadata that was always empty. Kept multiline and current text regressions.
- Fixed first-use dictionary saving by creating the missing parent directory
  before atomic write; its regression verifies a fresh store can reload the
  saved entry. This covers the iOS App Group's Dictionary subdirectory.
- Fixed number-word integer overflow by returning the original number run when
  arithmetic cannot fit; fixed capitalization of Unicode expansions such as
  `ß → SS` using string output. Both have focused regressions.
- Updated README, bundled Help, Mobile README, release/update instructions,
  regression documentation, remote status, deferred realtime design wording,
  public landing-page source, and stale Settings/meeting UI copy. Handoff now
  distinguishes current state from historical release snapshots.

## Open review findings

These existing behavior issues are recorded separately from stale-code removal;
fixing them requires dedicated behavior changes and the corresponding live gates.
Their follow-up state is `Not started`.

1. **P2 — overlapping pastes can interleave.** `MenuBarController.PasteGate`
   awaits a closure inside a reentrant actor. A second completed dictation can
   replace the clipboard during another's remote sync wait. A local harness
   using the exact actor body produced `first entered → second entered while
   first suspended → first exited`; no user clipboard or remote app was used.
   A proper queue/permit needs a concurrency regression and local/remote paste
   smoke. Suffix keys are also scheduled outside the paste gate.
2. **P2 — fully silent meeting streams can reach the provider.** Source review
   shows `prepareForChunking` returns the original URL when it detects no
   audible samples. OpenAI still chunks/uploads it; Deepgram queues a zero-offset
   stream. Distinguish confirmed silence from unreadable audio and test the
   complete session before changing this. No new live meeting reproduction is
   claimed.
3. **OpenAI meeting capture does not transcribe `phoneURL`.** Deepgram consumes
   the optional Phone/FaceTime process-tap stream; the OpenAI pipeline uses only
   mic and system streams. Documentation records the provider limitation.
4. **iOS lifecycle remains experimental.** Keyboard cancellation updates the
   exchange without immediately stopping the host recorder, and the separate
   App Intent recorder can reset an active exchange. The existing physical
   Notes gate must exercise cancellation and mixed-trigger behavior before this
   MVP is treated as complete. No physical reproduction was performed here.

## Verification boundary

The review, automated checks, local deployment, startup checks, and rendered
Help inspection are complete. No live dictation/paste, meeting capture, remote
desktop insertion, or physical iPhone Notes smoke was performed in this audit.
Those OS integration checks remain required for future changes to their active
runtime paths; the four open findings above retain their stated follow-up gates.
