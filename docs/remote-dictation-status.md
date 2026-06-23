# Remote Dictation Status

Last updated: 2026-06-23 after adding a Parsec remote-viewer paste target.

## Current Status

Remote dictation is inserting the current recording through formatting-preserving
paths. The post-0.7.21 finalization keeps the selected exact insertion routes
and makes paste operations asynchronous so remote clipboard synchronization
waits do not block the main actor or menu flow.

Current behavior:

- Screen Sharing/VNC sends the exact processed transcript through System Events
  text insertion first. Shared-clipboard remote Cmd+V and physical typing remain
  fallbacks.
- RustDesk writes the exact processed transcript to the local clipboard, waits
  for remote clipboard sync, then sends remote Cmd+V. Caps Lock-aware physical
  typing remains the fallback.
- Parsec sends the exact processed transcript through System Events text
  insertion first. Delayed remote Cmd+V and physical typing remain fallbacks.
- Paste Last Transcription uses the same async target-specific path as fresh
  dictation.
- If both the viewer Mac and controlled Mac have Vox running, turn on **Ignore
  Record Hotkey on This Mac** on the controlled/remote Mac. Otherwise one Fn
  press can start two Vox recordings and the remote instance can paste a second,
  bad, or stale transcription.

The historical failures addressed in this run were:

- The first letter of a dictated sentence is not capitalized.
- Questions are not ending with `?`.
- In at least one remote path, `?` was inserted as `/`, which means the remote
  session received the slash key without the Shift modifier.

Do not assume a future regression is "pasting the previous recording." That was
one earlier failure mode. The user explicitly corrected this after `v0.7.18`:
the later bug was capitalization and question punctuation.

The user has completed the remote testing for this finalization. If a future
failure is reported from a remote machine, local logs in this checkout may not
show that failing session.

## Known User Observations

- Current issue: in Screen Sharing/VNC, iMessage insertion can look clean, but
  remote apps including Wave and Notepad can receive the previous recording
  after Vox writes a newer transcript to the local clipboard.
- Current issue: Parsec was treated as `.standard`, so Vox used the immediate
  local paste path and could restore the prior clipboard instead of using a
  remote-client insertion path.
- Earlier issue: Vox inserted current text but lowercased the first letter and
  produced `/` instead of `?`.
- The user demonstrated the previous shifted-punctuation failure with dictated
  text such as lower-case sentence starts and question-like sentences ending in
  `/`.
- A Shift-based attempt turned `?` into `/`.
- Remote Control Mode in `v0.7.18` did not improve the user-observed behavior.
- On 2026-05-23, when the user was local on the Vox Mac and connected to a
  remote Mac with VNC, logs showed `processed=Is this not gonna work?` and
  `processed=Are you not going to capitalize the first letter?` before
  insertion, while the remote output still lost capitalization/question marks.
  This confirms the active failure is VNC insertion, not transcription or prose
  post-processing.
- After installing `v0.7.19`, logs showed the exact menu-paste path did not
  actually run: Screen Sharing returned `Edit > Send Clipboard is disabled` and
  `Edit > Paste is disabled`, then Vox fell back to physical typing. That
  fallback explains why capitalization and question marks were still broken.

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

### `v0.7.19`

Changes Screen Sharing/VNC back to exact text insertion through Screen Sharing's
shared clipboard/menu paste path, with physical typing only as a last fallback.
This is based on logs proving the processed text is already correct before
insertion, and on the observed fact that VNC key forwarding drops Shift/Caps
state needed for uppercase letters and `?`.

This release needs user validation.

User validation failed. The `v0.7.19` code still depended on Screen Sharing
menu items that were disabled in the user's session, so it fell back to the
physical typing path.

### `v0.7.20`

Restores the earlier exact Screen Sharing insertion route from the working
history:

- write the exact processed transcript to the local pasteboard;
- enable `Use Shared Clipboard` when that Screen Sharing menu item is available;
- wait for shared clipboard sync;
- send remote `Cmd+V` through System Events;
- only if that AppleScript keystroke fails, try Screen Sharing `Edit -> Paste`
  and then physical typing.

This specifically avoids treating disabled `Send Clipboard` or disabled
Screen Sharing `Edit -> Paste` menu items as a reason to immediately fall back
to physical typing.

### RustDesk exact-paste fix

Live RustDesk validation showed a Unicode-backed slash key event still inserted
`/`, not `?`. Current RustDesk did preserve exact text through local clipboard
paste plus remote `Cmd+V`, but immediate paste regressed to the old
one-recording-behind failure because RustDesk's remote clipboard sync can lag
behind the local pasteboard write. RustDesk now rewrites the local clipboard,
waits for sync, and then sends remote `Cmd+V`. Caps Lock-aware physical typing
remains only as the fallback if the AppleScript keystroke fails.

### Screen Sharing/VNC text-keystroke fix

Live VNC validation showed the shared clipboard path could paste the previous
recording even after waiting 3 seconds, despite `Use Shared Clipboard` being
checked. `Get Clipboard`, `Send Clipboard`, and Screen Sharing's own `Paste`
menu items were disabled in that session. System Events text `keystroke` into
the Screen Sharing window inserted current text with both uppercase letters and
`?` intact, so VNC now uses that route first. Shared-clipboard paste remains as
fallback only.

### Post-0.7.21 finalization

Regular dictation and Paste Last Transcription now call the async paste path.
The async path still prepares the pasteboard on the main actor, but remote
clipboard waits use `Task.sleep` instead of blocking the main thread. Suffix key
events are dispatched only after the awaited paste attempt completes.

The target capability helpers were updated to reflect reality: Screen
Sharing/VNC and RustDesk both have physical typing fallbacks, and Screen
Sharing/VNC can use a remote Cmd+V fallback after the System Events text route.
System Events text chunks now normalize `\r` and `\r\n` to newline key events.

### Post-0.7.23 intermittent Screen Sharing regression

After the 0.7.23 auto-relaunch release, the user reported that the remote
insertion failure was still intermittent and could corrupt the second sentence
of a dictation. The user then observed that recording on the viewer Mac also
triggered the remote Vox instance running on the controlled Mac. That is a
stronger fit for the symptom than paste-order alone: both instances can record
from different audio contexts and both can paste. Vox now has a menu-bar
toggle, **Ignore Record Hotkey on This Mac**, intended for the controlled/remote
Mac so forwarded Fn presses do not trigger that remote instance.

The user then confirmed the remote Vox process had already been killed, so the
dual-instance conflict was not the active cause for the visible garbled text.
They also noted that iMessage seems okay while Wave is the failing app. That
puts the failure back in the Screen Sharing/VNC insertion path, especially for
terminal-like receivers. Vox now uses the shared-clipboard remote Cmd+V route
first for Screen Sharing/VNC, with a longer 1.75 s clipboard-sync wait. System
Events text typing remains only as fallback if clipboard paste is unavailable.

After the 0.7.25 clipboard-first build, iMessage insertion looked clean, but
Wave still received the previous recording. 0.7.26 explicitly invoked Screen
Sharing's `Edit > Send Clipboard` after writing the new transcript to the local
clipboard, then waited 2.5 seconds before remote `Cmd+V`.

After the 0.7.26 Send Clipboard build, the stale previous-recording paste also
reproduced in Notepad. That means the active failure is not Wave-specific; it is
the shared clipboard route itself. 0.7.27 makes Screen Sharing/VNC try System
Events text insertion first, with smaller 24-character chunks and 0.04 s pauses,
so the primary path no longer depends on the remote shared clipboard. Shared
clipboard paste remains only as fallback.

## Current Code Paths

As of current main after the Parsec remote-viewer follow-up:

- `.standard` writes transcript to the pasteboard and sends `Cmd+V`.
- `.screenSharing` sends the exact processed transcript through System Events
  text insertion first, using conservative 24-character chunks with 0.04 s
  pauses. Only if that fails does it write the transcript to the local
  pasteboard, best-effort invoke `Send Clipboard`, wait for shared clipboard
  sync, and send remote `Cmd+V`.
- `.rustDesk` writes the exact processed transcript to the local pasteboard,
  waits for shared clipboard sync, then sends remote `Cmd+V` through System
  Events. It falls back to Caps Lock-aware physical typing if that keystroke
  fails.
- `.parsec` sends the exact processed transcript through System Events text
  insertion first. Only if that fails does it wait for remote clipboard sync,
  send remote `Cmd+V`, then fall back to Caps Lock-aware physical typing.
- `.remoteControl` uses Shift-modified physical typing for every frontmost app.
- `ignoreRecordHotkey` disables only the record hotkey on that Mac, leaving
  menu access, update checks, and Paste Last available.
- Regular dictation and Paste Last Transcription use the async paste path so
  remote sync waits do not block the main actor.

Remote targets skip restoring the previous clipboard:

- `.screenSharing`
- `.rustDesk`
- `.parsec`
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

Live validation is still needed in the user's remote Screen Sharing and Parsec
sessions. The active Screen Sharing symptom before `v0.7.27` was stale remote
clipboard delivery: remote apps including Wave and Notepad inserted the previous
recording even though iMessage insertion looked clean. The Parsec report before
this change was that transcript paste from a remote client did not work because
Parsec was not selected as a remote paste target.

## What Is Not Currently Broken

- The current user report is not that prose post-processing produces lowercase
  or missing-question-mark text locally.
- The current user report is not that both local and remote Vox instances are
  recording; the remote Vox process had already been killed.

## Historical Failure Boundary

The post-processing layer likely produces the right text locally: existing tests
cover prose first-letter capitalization and question-mark insertion.

The failure is more likely in remote insertion:

- Shift-modified physical key events are not reliable through Screen
  Sharing/VNC.
- Unicode-backed key events were also not reliable in prior VNC testing.
- Caps Lock physical typing is not reliable enough for first-letter uppercase
  and cannot type `?` without Shift.
- Exact text insertion requires a pasteboard/Accessibility path. The observed
  `v0.7.19` failure was that disabled Screen Sharing menu items caused an
  immediate fallback to physical typing. Later builds used shared clipboard
  sync plus remote `Cmd+V` before any physical fallback. `v0.7.26` added an
  explicit best-effort `Send Clipboard` push before pasting, but that still
  lagged in Wave and Notepad. `v0.7.27` therefore avoids the shared clipboard as
  the primary Screen Sharing/VNC path.

## If Remote Insertion Regresses

First identify whether the failure is stale remote clipboard delivery,
current-text corruption, capitalization, shifted punctuation, or a blocked
Accessibility/AppleScript path.

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

### Post-Parsec target follow-up

Parsec is detected by bundle identifier `tv.parsec.www` or by localized name.
When Vox is running on the viewer Mac with Parsec frontmost, Vox now chooses a
remote-viewer path instead of `.standard`: System Events text insertion first,
then delayed remote `Cmd+V`, then physical typing fallback. This avoids restoring
the previous local clipboard while Parsec may still be synchronizing clipboard
state to the host.

Live Parsec validation is still required because unit tests can cover target
selection and route policy, but not whether Parsec forwards AppleScript text
events, clipboard state, or modifier keys in the user's session.
