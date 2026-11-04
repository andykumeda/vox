# Deferred: meeting controls and recording retention

**Status: Not started. Timing: TBD.** Andy requested this document on November 4,
2026, for implementation at a later date. Do not implement these items merely
because an agent reads this document. At the start of future repository work,
review this document and call out these deferred requests and their status to
Andy before proceeding with the new task. Work on them when Andy explicitly asks.

| Workstream | Owner | Status | Acceptance criteria | Dependencies and verification | Release |
| --- | --- | --- | --- | --- | --- |
| Meeting control panel | Future implementer | Not started | Allow the meeting control popup to be minimized or moved, while recording continues and controls remain readily accessible. Confirm the intended behavior with Andy if the current hide behavior already satisfies the minimize request. | Inspect `Sources/vox/App/MeetingHUDPanel.swift` and callers; verify moving, hiding/restoring, active recording, screen changes and full-screen/Spaces behavior on a Mac. | Not deployed |
| Recording retention | Future implementer | Not started | Add a setting to retain meeting recordings and configure when they may be purged, with a **30-day default retention period**. Clearly show the setting and effective policy. | Resolve the decisions below before implementation. Review capture, store, cleanup, startup recovery and settings; use focused tests plus a live Mac verification. | Not deployed |

## Current behavior and scope

- `MeetingHUDPanel` has a close/hide action that does not stop a meeting, and
  configures the panel as movable by its background. It recreates and positions
  the panel near the menu bar on show. Actual usability and position persistence
  need verification; don't assume a drag setting alone meets the request.
- Meeting audio is currently temporary and is purged when processing completes,
  fails or is cancelled, and by a startup privacy sweep. Meeting transcripts are
  encrypted separately and remain until deleted. Review all `purgeAudio` and
  `purgeAllAudioArtifacts` callers, including failed-start and recovery paths.
- This request concerns **meeting recordings**, not dictation history or
  transcript retention. Previously purged recordings cannot be restored by a
  new setting. Avoid changing existing data or privacy behavior before the
  implementation is authorized and the decisions below are resolved.

## Decisions to resolve with Andy before implementation

1. Is recording retention enabled by default, or opt-in with 30 days as the
   default duration once enabled? How should existing installations migrate?
2. Which duration choices or custom values are wanted, and should there be a
   never-purge option? Define when the retention clock starts and whether a
   changed policy applies to existing recordings.
3. Should failed and cancelled meetings retain any usable recordings, and which
   source streams should be retained? Define manual deletion, meeting deletion,
   startup recovery, disk-space reporting, storage protection/encryption and
   behavior if retention or deletion fails. Preserve active recordings.
4. Is playback, export, or retranscription of retained recordings wanted? Those
   features are not authorized by this planning request and must not be assumed.
5. For the panel, clarify whether minimize means hide with a clear way to restore,
   a compact state, or a standard Dock-minimized window; confirm whether moved
   positions should persist across reopening, app restarts and display changes.

## Implementation and verification notes

Use the existing settings and meeting-store patterns; make deletion explicit,
bounded, and testable. Do not allow the startup sweep to erase eligible retained
audio or a timer to delete an active/in-progress capture. Account for corrupt or
inaccessible transcript metadata without silently deleting retained audio. Test
the default, policy changes, expiry boundaries, failures, restart recovery,
individual meeting deletion, and all recorded source streams. Verify that audio
retention and purging are accurately disclosed in Settings, Help and README.
Document actual tests, deployment and any remaining live checks in `HANDOFF.md`
and this ledger when work is eventually authorized. Follow the repository's
coordinated release procedure for implementation.
