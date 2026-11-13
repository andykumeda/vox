# Automatic meeting retranscription

| Workstream | Owner | Status | Acceptance |
| --- | --- | --- | --- |
| Authenticated archive extraction | Archive agent | Verified | Decrypt to a private temporary candidate only after integrity verification; no overwrite or plaintext residue on failure. |
| Recovery lifecycle | Codex | Verified | Automatically retry eligible preserved audio with the current meeting provider, bounded retries and no fallback; do not overwrite existing text or delete originals before a full candidate is saved. |
| Scheduling and user status | Codex | Verified | Recover eligible meetings at launch, wake and at the configured `meetingRecoveryInterval` (default 3600 seconds, minimum 60); persist attempts across restarts, serialize jobs and disclose provider uploads and charges. A cancellation stops automatic recovery for that meeting. |
| Release | Codex | Not started | 612 Swift tests and seven dictation fixtures pass; signed coordinated release and MacBook verification pending. |

Legacy recordings without saved source manifests and alignment cannot safely be declared
complete by guessing whether sources are missing or misaligned. Capture-loss warnings and missing original audio
remain review conditions. Provider text cannot be guaranteed word-for-word.
Playback and audio export remain deferred.

Recovery uses a private scratch directory, cleans it after use and removes stale
recovery directories at launch. If cleanup fails Vox displays a warning. Failed
retries preserve the saved transcript and original audio. Saved attempts use a
wall-clock timestamp across restarts; large clock changes can change retry timing.
A live provider request and physical meeting remain separate verification.
