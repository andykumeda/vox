# Transcript-first meeting audio protection

| Workstream | Owner | Status | Acceptance and verification |
| --- | --- | --- | --- |
| Detect incomplete transcripts | Codex | Verified | Empty source or chunk, missing capture or incomplete processing must not be presented as complete; preserve partial text. Focused empty and mixed-chunk tests pass. |
| Preserve audio | Recovery agent | Verified | Encrypt original and derived audio for failed, cancelled, interrupted, empty, partial and save-failed meetings independent of normal expiry, until complete or explicit deletion; preserve files when metadata or encryption fails. Restart, encryption failure and derived-only tests pass. |
| Release and MacBook | Codex | Not started | 588 Swift tests and seven dictation fixtures pass; signed coordinated production release and MacBook startup checks pending. Real meeting and live provider validation remain separate. |

These checks cannot verify word-for-word accuracy. Previously purged audio cannot
be restored by this change. Playback, audio export and retranscription remain
deferred; preserved recordings are not automatically retranscribed.
