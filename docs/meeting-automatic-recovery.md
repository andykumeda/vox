# Automatic meeting retranscription

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
