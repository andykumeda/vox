# OpenRouter meeting rate-limit retry

| Work | Status | Evidence |
| --- | --- | --- |
| Diagnose account | Verified | On November 13 the account showed $8.99 available; logs showed MAI-Transcribe 2 via Azure around the November 12 meeting. The precise 429 cause is not established. |
| Retry meeting HTTP 429 | Verified | Uses the existing configured meeting retry delays and budget, retaining the 429 if exhausted. Other HTTP errors fail immediately. A simulated 429 followed by success recovered its transcript; authentication failure remains non-retryable. |
| Release 0.7.87 / 111 | In progress | Full native Swift suite: 572 tests pass. Dictation regression: seven fixtures, quality 1.0, failure rate 0.0. Signed release installed on Mini and MacBook; public Pages feed remains on 0.7.86 while deployment is queued. A real MacBook meeting remains unverified. |

Previously failed meetings are not retranscribed by this change. Live rate-limit behavior and a real MacBook meeting remain to be verified.
