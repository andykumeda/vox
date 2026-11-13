# Meeting transcription reliability — November 2026

| Workstream | Owner | Status | Acceptance and verification |
| --- | --- | --- | --- |
| Provider retries and cancellation | Codex | Verified | Retry OpenAI/OpenRouter 429 and Deepgram transient failures without changing providers; respect OpenRouter Retry-After and configured deadline; cancellation remains cancellation. Focused simulated-provider tests pass, including Retry-After beyond the budget and cancellation of an overdue request. |
| Partial transcript | Codex | Verified | Save each Deepgram source as it completes; later failure/cancellation retains the visible partial result. Focused tests pass. |
| Save failure | Codex | In progress | Do not claim completion when the final transcript save fails; show an alert, prevent an unsaved result from being replaced, and retry saving before the next meeting. Audio remains in the running process. Restart protection depends on the opt-out retention decision. Fault injection passes. Current opt-out retention can remove audio after restart; the user was asked whether to permit an exception. |
| Release and MacBook | Codex | Not started | 583 Swift tests and seven dictation fixtures pass; signed release candidate 0.7.88 / 112 built. Production, public feed and MacBook install pending; real meeting and physical capture smoke remain separate. |

Do not infer a live provider success from mocked tests. Playback, audio export and retranscription remain deferred. Changes to opted-out audio retention require the user's decision.
