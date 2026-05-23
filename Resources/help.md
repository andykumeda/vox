# Vox — Quick Help

## Recording
Hold **Fn** (default) and speak. Release to transcribe.
Switch trigger to **tap-to-toggle** in Settings → Hotkeys if you prefer one-tap-start, one-tap-stop.

## Modes
- **Prose** — natural sentences, capitalized, with terminal punctuation. Default for most apps.
- **Command** — verbatim shell commands, no capitalization, no trailing punctuation. Auto-selected when the focused app is a terminal (Terminal, iTerm, Wave, etc.).
Press your **Mode toggle** hotkey (default `⌃⌥M`) to force prose regardless of focus. The menu-bar icon shows a lock when prose is forced.

## Verbatim mode
Smart Cleanup (Settings → Mode) polishes prose dictations conservatively — removes obvious false starts, fillers, self-corrections. Settings also includes a personal cleanup instructions editor saved at `~/Library/Application Support/Vox/cleanup-profile.md`; leave it empty for default behavior. Sometimes you want the literal text instead. Two ways to bypass cleanup for a single recording:

- **Hold Option while pressing Fn** — that recording is pasted raw, no cleanup, no trigger expansion.
- **Say "verbatim" or "literal" as the first word** of the dictation. The prefix is stripped and the rest is pasted as Whisper transcribed it. Example: speaking *"verbatim he literally said um maybe yeah"* pastes `he literally said um maybe yeah`.

## Dictionary
Settings → Dictionary lets you define custom substitutions:
- Spoken `vox` → replacement `Vox` (proper-noun fix in prose).
- Spoken `next field` → replacement `next tab` to insert "next" + Tab key.
- Mode scope: command, prose, or both.
- "Match only at start" anchors to the first word of an utterance.
12 built-in fixups are active behind the scenes (e.g., `ls -shell` → `ls -l`). To silence one, click **Reveal in Finder**, open `dictionary.json`, set `"enabled": false`, save. The change reloads automatically.

## Key-press substitutions
A replacement that ends with one of these words fires that key after pasting:
- `tab` — Tab (needs at least one preceding word)
- `return`, `enter`, `newline` — Return
- `escape`, `esc` — Esc
- `control X` — Ctrl+X (any letter)

## Meetings
Vox can transcribe meetings end-to-end by capturing system audio (the people on
the call, mixed by Zoom/Meet/etc) and your local mic in parallel.

- Press the **Meeting hotkey** (default `⌃⌥⇧M`) or pick **Meeting** from the
  menu-bar dropdown to open the floating Meeting panel.
- Click the **green Record disc** to start the session. Click the **red Stop
  square** to end it.
- Closing the panel with the `X` only hides the UI — recording continues.
  Re-open the panel via hotkey or menu to see the running timer or stop.
- When you click Stop, Vox transcribes via the configured meeting provider,
  interleaves segments by time, and opens the transcript browser.
- Meeting audio is kept in `~/Library/Application Support/Vox/MeetingTranscripts/<id>/`
  so you can replay or re-transcribe later. See **Settings → Recordings storage**
  to set a retention cutoff (default: delete audio after 1 month, transcripts
  always kept).

### Permissions for Meetings
- **Screen Recording** — required for system-audio capture via ScreenCaptureKit.
- **Microphone** — required for the local-mic stream.
Grant both in System Settings → Privacy & Security.

### Auto-show meeting panel
Settings → Meeting → **Auto-show meeting panel when a call starts**. When
on, Vox polls window titles every few seconds and pops the floating
panel as soon as a known meeting is detected:
- Teams (desktop + new "work or school" variant)
- Zoom desktop
- Webex desktop
- Slack huddle
- Discord voice/video call
- Skype call
- Google Meet, Microsoft Teams web, Zoom web, Webex web (active tab in
  Chrome / Safari / Edge / Arc / Brave / Firefox)

Recording is **never** auto-started — you still click Record on the
panel when you're ready. Disable any time in Settings.

### Meeting summary
Settings → Meeting → **Generate meeting summary after transcription**
(default on). After Vox finishes transcribing, it sends the segments
to gpt-4o-mini and stores a markdown summary with key decisions and
action items. The summary appears at the top of the transcript browser
(click the **Summary** disclosure to expand). Cost ~$0.0005 per
meeting. Summary is skipped silently if no API key.

### Quality tips
- Mic-side hallucinations (e.g. "I don't know." × 200) usually mean your mic was
  muted in Zoom while still hot at the OS level. Vox auto-collapses these
  cascades but you'll get a cleaner transcript if you mute Vox-side too:
  unplug the mic or switch the system input to a different device before the
  call.
- Whisper invents filler phrases ("you", "thanks for watching", "subscribe")
  on silent leading audio. Vox drops these automatically.
- macOS sometimes lets the mic input go silent mid-meeting (Teams renegotiates
  format, USB power management suspends the device, another app grabs
  exclusive access). Vox runs a watchdog every second and after 30 s of
  consecutive silence it tears down the recorder and starts a fresh one. Look
  for `MeetingMicCapture: 30s of silence → restarting recorder` in
  `~/Library/Logs/vox.log` if you suspect the mic dropped during a call.

## Hotkeys
Settings → Hotkeys lets you rebind:
- **Record dictation** (default Fn, press-and-hold).
- **Toggle mode** (default `⌃⌥M`, tap).
- **Meeting panel** (default `⌃⌥⇧M`, tap — toggles the floating Meeting panel).
- **Paste last transcription** (disabled by default — pick a combo to enable).
  Re-pastes the most recent dictation into the focused app. Also available
  from the Vox menu bar → "Paste Last Transcription".

## Files
- Dictionary: `~/Library/Application Support/Vox/dictionary.json`
- Smart cleanup profile: `~/Library/Application Support/Vox/cleanup-profile.md`
- Dictation history: `~/Library/Application Support/Vox/DictationHistory/history.json`
- Dictation recordings: `~/Library/Application Support/Vox/Recordings/`
- Meeting transcripts + audio: `~/Library/Application Support/Vox/MeetingTranscripts/`
- Logs: `~/Library/Logs/vox.log`

## Troubleshooting
- **Paste fails silently** — make sure Vox launched via `open dist/Vox.app`,
  not the binary directly. TCC attributes Accessibility permissions to the
  launching process.
- **Remote desktop paste fails** — Screen Sharing/VNC first sends exact text
  through System Events keystrokes so capitalization and question marks survive
  VNC clients that drop Shift/Caps Lock key forwarding; shared-clipboard Cmd+V
  and physical typing remain fallbacks. RustDesk writes the exact processed
  transcript to the local clipboard, waits for remote clipboard sync, then sends
  remote Cmd+V; Caps Lock-aware physical typing is the fallback. If you are
  remote-controlling the Mac that runs Vox,
  enable **Remote Control Mode** from the menu bar or Settings → Paste behavior.
- **Fn key doesn't fire** — System Settings → Keyboard → "Press 🌐 key to"
  must be **Do Nothing**.
- **Wrong transcription on short phrases** — add a Dictionary entry to fix
  the specific misfire (e.g., spoken `-shell` → `-l`).
- **Meeting recording starts but mic is silent** — happens when another app
  (or a prior meeting session) left CoreAudio holding the input device.
  Quitting Vox + reselecting the input device in System Settings → Sound
  usually clears it. `sudo killall coreaudiod` is the heavy hammer.
- **Dictation captures silence after a meeting** — Vox rebuilds its audio
  engine on each recording to avoid this, but if you ever see `peak=0` lines
  in `vox.log` immediately after a meeting, the mic device is stuck. Same
  recovery as above.
