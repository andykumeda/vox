# Transcript-first meeting audio protection

| Workstream | Owner | Status | Acceptance and verification |
| --- | --- | --- | --- |
| Detect incomplete transcripts | Codex | Deployed | Empty source or chunk, missing capture or incomplete processing must not be presented as complete; preserve partial text. Focused empty and mixed-chunk tests pass. |
| Preserve audio | Recovery agent | Deployed | Encrypt original and derived audio for failed, cancelled, interrupted, empty, partial and save-failed meetings independent of normal expiry, until complete or explicit deletion; preserve files when metadata or encryption fails. Restart, encryption failure and derived-only tests pass. |
| Release and MacBook | Codex | Deployed | 588 Swift tests and seven dictation fixtures pass; signed 0.7.89 / 113 installed on Mini and MacBook. MacBook microphone permission and hotkey startup pass. Public feed and 2,813,897-byte download match the signed DMG SHA-256 faabda09ea7b56b23e277611b2dfee8f823e53edf00fced7e8bfa12f24fd1a84. Pages run 43471062429 passed; hosted Release Gate and dictation regression were canceled before execution. A real meeting and live provider validation remain unverified. |

These checks cannot verify word-for-word accuracy. Previously purged audio cannot
be restored by this change. Playback, audio export and retranscription remain
deferred; preserved recordings are not automatically retranscribed.

The MacBook Vox meeting-storage folder contained no audio files at the time of this release; previously purged recordings cannot be reconstructed from that folder.

Automatic retranscription was subsequently requested on 2026-11-13; see
`docs/meeting-automatic-recovery.md` for current behavior. Playback and audio
export remain deferred.
