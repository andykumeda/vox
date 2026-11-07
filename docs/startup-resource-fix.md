# Packaged startup resource — 0.7.85 / 109

| Work | Status | Acceptance and evidence |
| --- | --- | --- |
| Diagnose MacBook startup | Verified | 0.7.84 crashed loading the SwiftPM resource: its generated accessor searched the app root and the build tree, while the bundle was in Contents/Resources. A build-tree copy temporarily restored startup. |
| Fix resource lookup | Verified | Prefer the app's packaged VoxCore resource; retain SwiftPM's lookup for other hosts. App-shaped bundle regression and all 570 Swift tests pass. Dictation regression: seven fixtures, quality 1.0, failure rate 0.0. |
| Release and MacBook validation | In progress | Build and sign 0.7.85/109 on AKsMini; publish matching source, DMG and Sparkle feed. Verify startup on the MacBook without the temporary build-tree copy. Spoken dictation and paste remain manual checks. |

The temporary SwiftPM native-build wrapper avoids the host's default build-system
SDK cache stall. Existing service configuration and provider routing are unchanged.
