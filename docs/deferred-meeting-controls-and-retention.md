# Meeting controls and recording retention

**Status: Deployed. Authorized: November 4, 2026.** Andy approved implementation
and the choices below. Playback, audio export and retranscription remain deferred.

| Workstream | Owner | Status | Acceptance criteria | Verification | Release |
| --- | --- | --- | --- | --- | --- |
| Meeting control panel | Panel implementer | Deployed | Hide/restore without stopping capture; remember dragged position across reopening/restarts; keep controls on an available display. | Four geometry tests pass; live move/hide/restore, screen changes and Spaces smoke pending. | 0.7.84 / 108 |
| Recording retention | Retention implementer | Deployed | Opt-in encrypted source recordings; 7/30/90 days, default 30; expiry from meeting end; apply changes to existing audio; retain available failed/cancelled captures; meeting deletion removes audio. | 569 Swift tests and seven dictation fixtures pass; live Mac smoke pending. | 0.7.84 / 108 |

## Approved policy

- Existing and new installs keep temporary meeting audio unless retention is enabled.
- Settings → Recordings storage exposes the toggle, duration and effective policy.
- Retain original system, microphone and Phone/FaceTime source streams locally;
  upload chunks and derived audio remain temporary. Dictation retention is unchanged.
- Count 24-hour days from meeting end (fall back to start for old records lacking
  an end). Changes apply to existing recordings. Disabling retention purges eligible
  existing audio at the next check; active recording/processing remains protected.
- Check expiry at launch, activation, wake, calendar day changes, after processing,
  and when Settings refreshes storage. Sleeping or stopped apps clean up on return.
- Each source is encrypted in bounded-memory authenticated ordered blocks using
  the existing Keychain history key. Verify the complete candidate before replacing
  an archive; remove plaintext only after every source has been encrypted successfully.
  Capture/upload files are temporarily unencrypted, as before.
- Preserve files on encryption/deletion failure and retry at the next check. Meeting
  warnings and Settings report maintenance failures. Unreadable/corrupt transcript
  metadata preserves audio, including during startup; check disk and Keychain access.
- Startup first marks interrupted sessions failed, then applies retention. Previously
  purged recordings cannot be recovered. Meeting deletion removes encrypted audio
  and transcript together; deletion is unavailable during recording/processing.
- Playback, audio export, retranscription, custom durations and never-purge are deferred.

## Verification and delivery

`swift test --build-system native`: **569 tests pass**, zero failures. Archive tests
cover tampering, ordering, truncation, cross-archive splicing and key errors. Store
checks cover defaults, exact expiry, changes, active protection, all source streams,
startup recovery, failures, deletion and a full mocked meeting lifecycle. The required
dictation regression script passes seven fixtures, quality 1.0 / failure rate 0.0.
The default Swift 6.4 build system stalled at SDK stat-cache provisioning; verification
used SwiftPM's native build system via a temporary wrapper for repository scripts.
Native UI inspection timed out; no rendered UI or physical recording proof is claimed.

Released [Vox 0.7.84 / 108](https://github.com/andykumeda/vox/releases/tag/v0.7.84).
Panel commit `917009f`, retention commit `7173b5f`, appcast commit `aa629a9`.
`build-app.sh` installed the production app; `make-dmg.sh` packaged it on AKsMini.
The final signed bundle was installed and LaunchAgent restarted (PID 67758).
Strict codesign, unchanged designated requirement, mounted DMG version/build,
installed/package executable equality, DMG checksum, bundled-key Ed25519 signature,
raw/live feed enclosure fields and anonymous public-download equality all pass.
Startup reports microphone permission, hotkey start and Accessibility trust.

Public DMG: **2,810,622 bytes**, SHA-256
`53ea60801699210ba630a4ed643f2cea1ebee81a2960d1144c9182b512b515cc`.
Installed/package executable SHA-256:
`07792532479723e8e44b898f2e847514d51c4a3f1ff572a42b12210e5f7cfd99`.
Source, installed bundle, GitHub release and public Sparkle feed agree on 0.7.84 / 108.
Pages deployment `41910883193`, Release Gate `41910887578` and source Dictation
Regression `41910883916` passed.

Live checks still required: drag/hide/restore while recording, restart persistence,
display removal/full-screen/Spaces, a real retained multi-source meeting, settings
policy changes, permission preservation and second-Mac Sparkle installation.


## Native controls and Mini hang follow-up (2026-11-09)

| Work | Status | Acceptance and verification |
| --- | --- | --- |
| Native panel | Deployed | AppKit title bar with close, minimize and zoom. The installed Mini window displayed all three controls and minimizing removed it from view. Automation did not establish title-bar movement or restore after minimize. A real recording through close/restore and display/Spaces behavior remain manual checks. |
| Post-meeting hang | Deployed | A Mini process sample showed audio cleanup holding the transcript lock while synchronous notification delivery waited for the main thread. The UI was waiting to read that same store. Restart recovered the process. Cleanup now publishes changes after unlocking, and the regression verifies that an observer can read the updated store before notification delivery returns. |

Vox 0.7.86 / 110 is installed on the Mini and available via Sparkle. Panel
commit `38661f8`, store commit `b9a7c02` and release commit `edcda5a`.
The restarted LaunchAgent reported microphone permission, hotkey initialization
and Accessibility trust. A post-install sample showed an idle AppKit event loop.
A real post-meeting completion with the new build and a second-Mac update remain
unverified.

All 571 local Swift tests and seven dictation regression fixtures passed using the
native SwiftPM build system. Hosted Release Gate `42719049828` and Dictation
Regression `42719049755` were canceled before execution because GitHub rejected
the configured `macos-14-arm64-us-default` runner. Pages `42719048323` passed.

The public DMG matches the installed executable and passed strict signing,
version/build, checksum and bundled-key Ed25519 checks. The live feed matches
the signed enclosure URL, signature and 2,799,733-byte length. DMG SHA-256
`199a6ce0a29e54ade574c0abc1d37534775ba41aaeba0c81082b940e24255c64`.
