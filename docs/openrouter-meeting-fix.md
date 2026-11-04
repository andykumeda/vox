# OpenRouter meeting audio fix

| Work | State | Evidence / remaining work |
| --- | --- | --- |
| Diagnose HTTP 400 | Verified | MacBook meeting capture completed. Identical synthetic requests to MAI-Transcribe-2 returned HTTP 400 for M4A and HTTP 200 with timestamped segments for WAV. Temporary capped diagnostic keys were deleted. |
| Convert meeting audio | Verified | OpenRouter meeting chunks convert to 16 kHz mono PCM WAV before upload; provider selection, timing offsets, and audio cleanup remain unchanged. Focused tests exercise AAC input and WAV payload. |
| Regression | Verified | Full Swift suite and seven dictation fixtures pass. |
| Production release 0.7.82 / 106 | In progress | Coordinated install, source, signed DMG, and public Sparkle release pending. |
| MacBook live meeting | Not started | Verify a new real OpenRouter meeting on the MacBook after update. The 2026-11-04 failed meeting's audio was purged under the existing terminal cleanup policy and was not found in its session folder. |

The Mini was configured for Deepgram meetings when investigated; the user reports
a successful meeting there two days earlier. OpenRouter conversion is shared by
both Macs when selected. No live meeting success is claimed by synthetic tests.
