# Automatic meeting retranscription

## Silent-source recovery follow-up (2026-11-13)

| Workstream | Owner | Status | Acceptance and evidence |
| --- | --- | --- | --- |
| Silent-source recovery | Codex | Verified | A valid speech result must not fail because a separate source is exact digital silence. Nonzero and unreadable sources must still be processed; all-silent recordings must not be claimed complete. A real-audio regression failed before the fix and passes afterward; 615 Swift tests and seven dictation fixtures pass. |
| Failure detail | Codex | Verified | Failed recovery reports the candidate failure without replacing the original failure or deleting saved audio. Covered by recovery tests. |
| Release and MacBook retry | Codex | Deployed | Signed 0.7.92 / 116 installed on Mini and MacBook; public feed, release asset, SHA-256 and Sparkle signature match. The preserved MacBook test retried automatically, reached Done, and its Other transcript visually matches the complete synthetic script. Temporary audio was removed. |
| Mini recovery smoke | Codex | Blocked | A synthetic test was interrupted by an agent restart while waiting for Stop, before source alignment was saved. Vox retained the three encrypted sources and reported that review is required. Normal Deepgram provider and retry defaults were restored; a controlled stop and successful recovery are still required. |

On the MacBook's 34-second synthetic test, the initial request was intentionally
rejected and recovery sent three sources to OpenRouter; the phone source was logged
below the existing silence threshold. The test reproduced rejection of a silent
source. With 0.7.92 the same archived meeting skipped the phone source and generated
a summary after processing its other sources. The Other transcript contains all
six synthetic sentences, including the last. A duplicated You segment ends early
after the microphone picked up speaker output; this was not a multi-person call.
Only an entire successfully decoded, nonempty source of zero samples is omitted.
The silence threshold alone is not used to declare completion.

| Workstream | Owner | Status | Acceptance |
| --- | --- | --- | --- |
| Authenticated archive extraction | Archive agent | Deployed | Decrypt to a private temporary candidate only after integrity verification; no overwrite or plaintext residue on failure. |
| Recovery lifecycle | Codex | Deployed | Automatically retry eligible preserved audio with the current meeting provider, bounded retries and no fallback; do not overwrite existing text or delete originals before a full candidate is saved. |
| Scheduling and user status | Codex | Deployed | Recover eligible meetings at launch, wake and at the configured `meetingRecoveryInterval` (default 3600 seconds, minimum 60); persist attempts across restarts, serialize jobs and disclose provider uploads and charges. A cancellation stops automatic recovery for that meeting. |
| Release | Codex | Deployed | 613 Swift tests and seven dictation fixtures pass. Signed 0.7.91 / 115 is installed on Mini and MacBook; MacBook microphone permission and hotkey startup pass. Public feed matches the 2,867,339-byte signed DMG and anonymous download SHA-256 e2033b8424d24cfbb955934cd752d4bc4f81f2627886ebb56d752987ce1aeeb9. Pages run 43476224845 passed; hosted Release Gate and dictation regression jobs were canceled before execution. |

Legacy recordings without saved source manifests and alignment cannot safely be declared
complete by guessing whether sources are missing or misaligned. Capture-loss warnings and missing original audio
remain review conditions. Provider text cannot be guaranteed word-for-word.
Playback and audio export remain deferred.

Recovery uses a private scratch directory, cleans it after use and removes stale
recovery directories at launch. If cleanup fails Vox displays a warning. Failed
retries preserve the saved transcript, original failure explanation and original audio.
The initial 0.7.90 build may have replaced older failure explanations when recovery
could not start; the follow-up prevents further replacement but cannot reconstruct
those explanations. Saved attempts use a
wall-clock timestamp across restarts; large clock changes can change retry timing.
A live provider request and physical meeting remain separate verification.
