# OpenRouter meeting audio fix

| Work | State | Evidence / remaining work |
| --- | --- | --- |
| Diagnose HTTP 400 | Verified | MacBook meeting capture completed. Identical synthetic requests to MAI-Transcribe-2 returned HTTP 400 for M4A and HTTP 200 with timestamped segments for WAV. Temporary capped diagnostic keys were deleted. |
| Convert meeting audio | Verified | OpenRouter meeting chunks convert to 16 kHz mono PCM WAV before upload; provider selection, timing offsets, and audio cleanup remain unchanged. Focused tests exercise AAC input and WAV payload. |
| Regression | Verified | Full Swift suite and seven dictation fixtures pass. |
| Production release 0.7.82 / 106 | In progress | Source `00dc449` and GitHub release published; signed DMG SHA-256 `c712e833c60df626d11d017cf275ea3f2ff176a2b2023ba8337cc4db2755065a` matches anonymous download. Mini and MacBook installed/restarted matching executable SHA-256 `646fc5cffa79ec748a197bd90305f3ed23420bd0ae2175bb6f29af0a8048a4bb`; microphone permission and hotkey startup logged. GitHub Pages run `41877845128` queued; public feed still advertises 0.7.81 / 105. Confirm public feed and CI before calling coordinated release complete. |
| MacBook live meeting | Not started | Verify a new real OpenRouter meeting on the MacBook after update. The 2026-11-04 failed meeting's audio was purged under the existing terminal cleanup policy and was not found in its session folder. |

The Mini was configured for Deepgram meetings when investigated; the user reports
a successful meeting there two days earlier. OpenRouter conversion is shared by
both Macs when selected. No live meeting success is claimed by synthetic tests.
