# Remote Dictation Status

Last updated: 2026-05-23 after user testing `v0.7.18`.

## Current Status

Remote dictation is inserting the current recording again, but the inserted text
is still not formatted correctly in the remote session.

The active failures are:

- The first letter of a dictated sentence is not capitalized.
- Questions are not ending with `?`.
- In at least one remote path, `?` was inserted as `/`, which means the remote
  session received the slash key without the Shift modifier.

Do not describe the current bug as "pasting the previous recording." That was an
earlier failure mode. The user explicitly corrected this after `v0.7.18`: the
remaining bug is capitalization and question punctuation.

The user is testing remotely. Local logs in this checkout may not show the
failing session, and prior debugging based on local process/log state was not
useful.

## Known User Observations

- Earlier issue: Vox pasted the previous recording instead of the most recent
  one.
- Current issue: Vox inserts the current text, but it is lowercasing the first
  letter and not producing question marks.
- The user demonstrated the current failure with dictated text such as
  lower-case sentence starts and question-like sentences ending in `/`.
- A Shift-based attempt turned `?` into `/`.
- Remote Control Mode in `v0.7.18` did not improve the user-observed behavior.

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

These releases targeted one-recording-behind remote pastes.

### `v0.7.12`

Added prose-looking first-letter capitalization for remote targets. RustDesk
switched back to the Caps Lock physical typing path.

### `v0.7.13`

Restored Screen Sharing/VNC to Caps Lock-aware physical typing with no shared
clipboard dependency. This was intended to prevent remote clipboard lag from
inserting the previous transcription.

This is a candidate for the point where "current recording insertion" was fixed,
but it still approximates shifted punctuation such as `?`.

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

This was intended to restore current-recording insertion reliability. It did not
solve the active capitalization/question-mark issue.

### `v0.7.18`

Added explicit Remote Control Mode for the topology where Vox runs on the Mac
being controlled remotely. In that setup the frontmost app is the target app,
not the VNC/RustDesk viewer, so automatic VNC/RustDesk frontmost-app detection
does not select the remote path.

Remote Control Mode forces direct physical typing for every frontmost app.
However, it currently uses Shift-modified physical typing, so if the remote
session drops synthetic Shift, the expected failure is exactly what the user is
seeing: first letters remain lowercase and `?` becomes `/`.

The user reported that Remote Control Mode does not fix the remaining issue.

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

- First-letter capitalization is not surviving remote insertion.
- Question punctuation is not surviving remote insertion.
- `?` can become `/` when the current path relies on synthetic Shift.
- Remote Control Mode did not fix those formatting failures.

## What Is Not Currently Broken

- The current user report is not that Vox pastes the previous recording.
- Current-recording delivery appears to be working well enough for the user to
  show the formatting failures in dictated text.

## Likely Failure Boundary

The post-processing layer likely produces the right text locally: existing tests
cover prose first-letter capitalization and question-mark insertion.

The failure is more likely in remote insertion:

- Shift-modified physical key events are not reliable through the remote path.
- Unicode-backed key events were also not reliable in prior VNC testing.
- Caps Lock can help uppercase letters in some paths, but it cannot type `?`
  without Shift.
- Exact text insertion may require a pasteboard/menu/Accessibility path, but
  earlier shared-clipboard approaches caused stale paste problems.

## Next Debugging Session

Do not spend the next session debugging "previous recording paste" unless the
user reports that it has regressed. The active problem is shifted-character and
capitalization fidelity.

Recommended sequence:

1. Add a visible diagnostic before insertion that shows:
   - the exact processed text Vox is about to insert;
   - selected paste target;
   - whether Remote Control Mode is enabled;
   - selected physical typing mode.
2. Add explicit menu commands to separate concerns:
   - "Copy Last Processed Text" to confirm post-processing output;
   - "Type Last Processed Text" to test physical typing only;
   - "Paste Last Processed Text" to test clipboard paste only.
3. For Remote Control Mode, test three insertion strategies against the same
   known string, for example `Why is this not working?`:
   - Caps Lock-aware physical typing;
   - Shift-modified physical typing;
   - exact paste after a delay without restoring the clipboard.
4. Only after the working insertion strategy is identified should it be made the
   default for remote use.

## Practical Priority

The priority is now exact enough remote text insertion for normal prose:

- preserve first-letter capitalization;
- preserve question marks;
- avoid reintroducing the older previous-recording clipboard bug.
