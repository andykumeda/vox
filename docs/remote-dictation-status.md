# Remote Dictation Status

Last updated: 2026-05-23 after release `v0.7.18`.

## Current Status

Remote dictation insertion is still broken for the user.

The reported failure is that, when dictating through a remote-control session,
Vox pastes the previous recording instead of the most recent recording. Recent
attempts also exposed related fidelity failures: first-letter capitalization was
lost in some paths, and question marks became `/` when a VNC/Screen Sharing path
dropped Shift.

The user is testing remotely. Do not assume local logs in this checkout show the
failing session. In prior debugging, relying on visible local logs/processes was
misleading because the affected Vox instance and remote desktop session may be
on a different host or user context.

## Known User Observations

- The bug was originally: "not transcribing the most recent recording."
- The user said this would not appear in the available logs because they are
  remote.
- RustDesk had previously been involved accidentally, then the user switched
  back to macOS Screen Sharing/VNC.
- VNC/Screen Sharing continued to paste the previous recording.
- Later builds got current paste working in at least one moment, but first-letter
  capitalization still failed and question marks were not inserted.
- A Shift-based attempt turned `?` into `/`.
- The user stated that VNC used to work several commits earlier.
- `v0.7.18` Remote Control Mode was tested by the user and "does nothing";
  behavior remained the same.

## Release Timeline

### `v0.7.2`

Added app-specific remote paste handling.

- Screen Sharing/VNC used a System Events paste fallback because standard
  synthesized `Cmd+V` could lose modifiers inside a remote session.
- RustDesk avoided paste shortcuts and typed plain physical keypresses because
  RustDesk dropped synthetic modifier keys.

### `v0.7.3`

Kept dictated text on the local clipboard for VNC targets to avoid restoring the
previous clipboard before the remote side consumed the transcript.

### `v0.7.4`

Tried a VNC clipboard synchronization path:

- wait briefly for remote clipboard sync;
- invoke local `Edit -> Paste`;
- fall back to key-event paste.

### `v0.7.5`

Moved Screen Sharing/VNC away from remote clipboard paste and typed dictation
directly into the VNC session as physical key events. RustDesk stayed on
unmodified physical typing.

### `v0.7.6`

Tried Unicode text key events for VNC capitalization instead of Shift-modified
physical key events.

### `v0.7.7`

Tried Caps Lock around uppercase letter runs for VNC/RustDesk, attempting to
avoid dropped Shift/Unicode payloads.

### `v0.7.8`

Returned Screen Sharing/VNC to a shared-clipboard paste path for better
capitalization/punctuation when shared clipboard was available. RustDesk stayed
best-effort physical typing because live testing showed RustDesk menu paste
inserted nothing and synthetic modifiers were unreliable.

### `v0.7.9` through `v0.7.11`

Iterated on Screen Sharing/VNC shared-clipboard behavior:

- write new transcript to the local clipboard;
- refresh Screen Sharing's shared clipboard;
- explicitly invoke `Send Clipboard` when available;
- treat clipboard push as best-effort instead of aborting.

These releases targeted one-recording-behind remote pastes, but the user still
saw stale insertion behavior.

### `v0.7.12`

Added prose-looking first-letter capitalization for remote targets. RustDesk
switched back to the Caps Lock physical typing path.

### `v0.7.13`

Restored Screen Sharing/VNC to Caps Lock-aware physical typing with no shared
clipboard dependency. This was intended to prevent remote clipboard lag from
inserting the previous transcription.

This is the most important historical candidate for "last known working" because
it explicitly bypassed the shared clipboard. However, the user has not confirmed
that `v0.7.13` itself works in the current remote setup.

### `v0.7.14`

Tried explicit Shift-modified physical key events for VNC capitalization and
question marks. User observed `?` became `/`, which means VNC/Screen Sharing
dropped the synthetic Shift modifier.

### `v0.7.15`

Tried Unicode-backed physical key events for shifted characters. This did not
fix the observed VNC behavior; the client still behaved like it received raw
unshifted keycodes.

### `v0.7.16`

Tried exact Screen Sharing menu paste after refreshing shared clipboard twice.
User reported VNC still did not work.

### `v0.7.17`

Reverted Screen Sharing/VNC to the `v0.7.13` style Caps Lock-aware physical
typing path:

- no shared clipboard refresh;
- no menu paste;
- no clipboard sync wait.

This was based on commit history, but it did not solve the user's remote test.

### `v0.7.18`

Added explicit Remote Control Mode for the different topology where Vox runs on
the Mac being controlled remotely. In that setup the frontmost app is the target
app, not the VNC/RustDesk viewer, so automatic VNC/RustDesk frontmost-app
detection does not select the remote path.

Remote Control Mode forces direct physical typing for every frontmost app and
keeps the transcript from being restored off the clipboard.

The user reported that Remote Control Mode does nothing and the behavior remains
the same.

## Current Code Paths

As of `v0.7.18`:

- `.standard` writes transcript to the pasteboard and sends `Cmd+V`.
- `.screenSharing` uses Caps Lock-aware physical typing.
- `.rustDesk` uses Caps Lock-aware physical typing.
- `.remoteControl` uses Shift-modified physical typing for every frontmost app.

Remote targets skip restoring the previous clipboard:

- `.screenSharing`
- `.rustDesk`
- `.remoteControl`

Remote Control Mode is stored in `UserDefaults` under:

```text
remoteControlModeEnabled
```

The implementation files are:

- `Sources/vox/Text/TextInjector.swift`
- `Sources/vox/Util/AppSettings.swift`
- `Sources/vox/App/MenuBarController.swift`
- `Sources/vox/App/SettingsWindow.swift`

## What Is Still Broken

- The user still sees the previous recording pasted in remote use.
- VNC/Screen Sharing has not been restored to the user-confirmed working state.
- RustDesk is not confirmed working.
- Remote Control Mode did not change the user's observed behavior.
- Capitalization and question-mark fidelity remain secondary unresolved issues;
  the primary unresolved issue is current-recording delivery.

## What We Do Not Know

- The exact last version that worked in the user's real remote setup.
- Whether the remote Mac is actually running the updated build after Sparkle
  update and relaunch.
- Whether the failing insertion happens through `TextInjector.paste`, Paste Last
  Transcription, a stale history entry, a stale clipboard, or an older Vox
  process.
- Whether the transcript text is correct before insertion on the affected
  machine.
- Whether the remote-control software is synchronizing clipboard contents after
  Vox writes the current transcript but before the target app consumes it.
- Whether physical key events are being posted but ignored by the focused remote
  target.

## Next Debugging Session

Avoid more blind release iterations. First establish the exact working boundary.

Recommended sequence:

1. Test old release DMGs on the actual remote Mac, starting with `v0.7.13`,
   then `v0.7.5`, then `v0.7.2`.
2. For each version, record only these outcomes:
   - does it insert the current recording?
   - does it paste the previous recording?
   - does it insert nothing?
   - does capitalization/punctuation matter?
3. Add a user-visible diagnostics surface before another insertion fix:
   - show the selected paste target in a notification or menu item;
   - show whether Remote Control Mode is enabled;
   - show the exact text that Vox is about to insert;
   - optionally add "Copy Last Processed Text" and "Type Last Processed Text"
     menu commands to separate transcription from insertion.
4. Once the actual last-good release is confirmed, diff that version against the
   first bad version and revert only the insertion path that changed.

## Working Hypotheses

These are unproven and should not be treated as facts:

- The failing remote setup may not be using the newly released build, or it may
  have an older Vox process still running.
- The stale text may be coming from dictation history or paste-last state rather
  than the clipboard.
- The remote-control client may be overriding the local pasteboard after Vox
  writes the current transcript.
- Direct physical typing may be ignored by the target app or by macOS security
  permissions on the affected remote Mac.

## Practical Priority

The priority is not punctuation or capitalization. The priority is to restore
one reliable remote path that inserts the current recording. Once that is stable,
capitalization and question mark fidelity can be revisited.
