# Remote Dictation Status

Last reviewed: 2026-07-28.

## Current Status

Remote dictation inserts the current recording through formatting-preserving
paths. Paste is asynchronous so remote clipboard waits do not block the main
actor or menu flow. Paste operations (fresh dictation and Paste Last) are
serialized.

Current behavior:

- Paste locks the frontmost process id / bundle at paste start. Screen Sharing
  AppleScript menu actions target that unix id. If focus drifts mid-paste, Vox
  aborts further injection and leaves the transcript on the clipboard.
- Screen Sharing/VNC sends the exact processed transcript through System Events
  text insertion first. Shared-clipboard remote Cmd+V and Unicode-backed
  physical typing remain fallbacks.
- RustDesk writes the exact processed transcript to the local clipboard, waits
  (polling focus during the delay) for remote clipboard sync, then sends remote
  Cmd+V. Unicode-backed physical typing remains the fallback.
- Parsec sends the exact processed transcript through System Events text
  insertion first. Delayed remote Cmd+V and Unicode-backed physical typing
  remain fallbacks.
- **Remote Control Mode** applies only when the frontmost app is not a known
  outbound viewer. Screen Sharing, RustDesk, and Parsec keep their specialized
  paths even when the mode is enabled. Use Remote Control Mode when this Mac is
  being controlled and the frontmost target is a normal local app.
- Paste Last Transcription uses the same async target-specific path as fresh
  dictation, and is ignored while a dictation cycle is already busy.
- If both the viewer Mac and controlled Mac have Vox running, turn on **Ignore
  Record Hotkey on This Mac** on the controlled/remote Mac. Otherwise one Fn
  press can start two Vox recordings.

Do not assume a future regression is only "pasting the previous recording."
Historical failures also included lost capitalization and `?` becoming `/` when
synthetic Shift was dropped. Physical fallbacks now prefer Unicode-backed
shifted characters instead of Caps Lock mangling.

## Current Code Paths

- `.standard` writes transcript to the pasteboard and sends `Cmd+V`.
- `.screenSharing` System Events text first; then best-effort `Send Clipboard`,
  focus-aware wait, remote `Cmd+V` / Edit > Paste; then Unicode-backed physical
  typing.
- `.rustDesk` clipboard + focus-aware wait + remote `Cmd+V`; Unicode-backed
  physical fallback.
- `.parsec` System Events text first; then wait + remote `Cmd+V`; Unicode-backed
  physical fallback.
- `.remoteControl` Shift-modified physical typing for ordinary local apps only
  (not when a specialized viewer is frontmost).
- `ignoreRecordHotkey` disables only the record hotkey on that Mac.

Remote targets skip restoring the previous clipboard:
`.screenSharing`, `.rustDesk`, `.parsec`, `.remoteControl`.

Remote Control Mode key: `UserDefaults` `remoteControlModeEnabled`.

## Historical Failure Modes (do not re-debug blindly)

- Stale previous recording pasted via remote shared clipboard lag.
- Parsec treated as `.standard` (immediate local paste + clipboard restore).
- Caps Lock / Shift physical fallbacks dropping capitalization or turning `?`
  into `/` or `.`.
- Remote Control Mode overriding outbound viewer paths when both were needed.
- `Edit > Send Clipboard` / `Edit > Paste` disabled in Screen Sharing, falling
  through to a broken physical path.

## Release Timeline (abridged)

See git history for `TextInjector.swift` and tags `v0.7.2`–`v0.7.28` for the
full iteration (System Events, shared clipboard, Caps Lock, Unicode, Parsec,
async paste). The paths above supersede Caps Lock-as-production-fallback notes
in older release blurbs.
