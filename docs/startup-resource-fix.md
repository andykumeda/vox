# Packaged startup resource — 0.7.85 / 109

| Work | Status | Acceptance and evidence |
| --- | --- | --- |
| Diagnose MacBook startup | Verified | 0.7.84 crashed loading the SwiftPM resource: its generated accessor searched the app root and the build tree, while the bundle was in Contents/Resources. A build-tree copy temporarily restored startup. |
| Fix resource lookup | Verified | Prefer the app's packaged VoxCore resource; retain SwiftPM's lookup for other hosts. App-shaped bundle regression and all 570 Swift tests pass. Dictation regression: seven fixtures, quality 1.0, failure rate 0.0. |
| Release and MacBook validation | In progress | Signed 0.7.85/109 installed on Mini and MacBook. MacBook starts with the temporary build-tree copy moved away; microphone permission and hotkey startup confirmed. Source 6407bfe and GitHub release published; public Sparkle feed verification pending. Spoken dictation and paste remain manual checks. |

The temporary SwiftPM native-build wrapper avoids the host's default build-system
SDK cache stall. Existing service configuration and provider routing are unchanged.
Signed DMG SHA-256: `264bc8ff5cb1cc4c12dc4c49a8efe0e527a8c115e8030994cc1e4feb371415fc`.
Both installed executables SHA-256: `0f3391e0ee83c68f23b37cdce7a4026df895e7546c49ae4fe7dc9ed001103124`.
