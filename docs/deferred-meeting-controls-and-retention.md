# Meeting controls and recording retention

**Status: In progress. Authorized: November 4, 2026.** Andy approved implementation
and the choices below. Playback, audio export and retranscription remain deferred.

| Workstream | Owner | Status | Acceptance criteria | Verification | Release |
| --- | --- | --- | --- | --- | --- |
| Meeting control panel | Panel implementer | In progress | Hide/restore without stopping capture; remember dragged position across reopening/restarts; keep controls on an available display. | Four geometry tests pass; live move/hide/restore, screen changes and Spaces smoke pending. | Not deployed |
| Recording retention | Retention implementer | In progress | Opt-in encrypted source recordings; 7/30/90 days, default 30; expiry from meeting end; apply changes to existing audio; retain available failed/cancelled captures; meeting deletion removes audio. | 569 Swift tests and seven dictation fixtures pass; live Mac smoke pending. | Not deployed |

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

Implementation is not yet released. Record actual test and production evidence here
and in HANDOFF.md before handoff. The coordinated release must align installed app,
committed source, signed GitHub DMG and public Sparkle feed on a unique version/build.

Live checks still required: drag/hide/restore while recording, restart persistence,
display removal/full-screen/Spaces, a real retained multi-source meeting, settings
policy changes, permission preservation and second-Mac Sparkle installation.
