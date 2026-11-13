# OpenRouter meeting rate-limit retry

| Work | Status | Evidence |
| --- | --- | --- |
| Diagnose account | Verified | On November 13 the account showed $8.99 available; logs showed MAI-Transcribe 2 via Azure around the November 12 meeting. The precise 429 cause is not established. |
| Retry meeting HTTP 429 | Verified | Uses the existing configured meeting retry delays and budget, retaining the 429 if exhausted. Other HTTP errors fail immediately. A simulated 429 followed by success recovered its transcript; authentication failure remains non-retryable. |
| Release 0.7.87 / 111 | Deployed | Full native Swift suite: 572 tests pass. Dictation regression: seven fixtures, quality 1.0, failure rate 0.0. Signed release installed on Mini and MacBook; public Pages feed advertises 0.7.87 / 111 and the public DMG SHA-256 matches the signed artifact (b1d6e73b3d828486fb6f9932f1c0c58ceb37b164e83ec57d587f9c81b388a0db). Hosted release and regression jobs were canceled before execution. A real MacBook meeting remains unverified. |

Previously failed meetings are not retranscribed by this change. Live rate-limit behavior and a real MacBook meeting remain to be verified.
