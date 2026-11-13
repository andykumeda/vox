# Meeting transcription reliability — November 2026

| Workstream | Owner | Status | Acceptance and verification |
| --- | --- | --- | --- |
| Provider retries and cancellation | Codex | Deployed | Retry OpenAI/OpenRouter 429 and Deepgram transient failures without changing providers; respect OpenRouter Retry-After and configured deadline; cancellation remains cancellation. Focused simulated-provider tests pass, including Retry-After beyond the budget and cancellation of an overdue request. |
| Partial transcript | Codex | Deployed | Save each Deepgram source as it completes; later failure/cancellation retains the visible partial result. Focused tests pass. |
| Save failure | Codex | Blocked | Do not claim completion when the final transcript save fails; show an alert, prevent an unsaved result from being replaced, and retry saving before the next meeting. Audio remains in the running process. Restart protection depends on the opt-out retention decision. Fault injection passes. Current opt-out retention can remove audio after restart; the user was asked whether to permit an exception. |
| Release and MacBook | Codex | Deployed | 583 Swift tests and seven dictation fixtures pass; signed 0.7.88 / 112 installed on Mini and MacBook, both report microphone permission and hotkey startup. Public feed matches the signed 2,811,202-byte DMG, whose downloaded SHA-256 is f450716b88eb4b4174310ccd1ec4da412ae831b0ac9024adbe40cc41d4bd5ecd. Pages run 43453599714 passed; hosted Release Gate and regression were canceled before running. Real meeting and physical capture smoke remain unverified. |

Do not infer a live provider success from mocked tests. Playback, audio export and retranscription remain deferred. Changes to opted-out audio retention require the user's decision.

Retry deadlines rely on request operations cooperating with cancellation; synchronous conversion can delay cancellation. Provider tests use synthetic stubs, not live service errors.
