# Vox — Quick Help

## Getting started

Open the Vox menu-bar icon → **Settings**, save your OpenAI API key, and grant Microphone, Input Monitoring, and Accessibility in System Settings → Privacy & Security. Meeting transcription also needs Screen Recording.

The menu contains **Dashboard**, **Meeting**, **Paste Last Transcription**, **Settings**, **Check for Updates…**, **Help**, and **Quit Vox**. Dashboard opens Home with recent dictations and meetings. **Quit Vox** stops the app normally; closing a window does not quit it.

## Recording

Hold **Fn** (default) and speak. Release to transcribe.
Switch trigger to **tap-to-toggle** in Settings → Hotkeys if you prefer one-tap-start, one-tap-stop.
A start sound plays before the microphone opens; a stop sound plays after you release. Vox prepares the start cue silently after launch to reduce the first-recording delay. Bluetooth output can still take time to wake. Change or silence either cue in Settings → Sounds.
Choose Settings → Microphone to pin dictation to a specific input device. While Vox runs, it keeps that mic as the macOS default input through output changes and device reconnects, and will not silently fall back to Bluetooth. If another app leaves its writable macOS input level below 70%, Vox restores it to 75% before recording; normal levels and devices without software volume controls are unchanged.
Dictation uses `gpt-4o-transcribe` by default for accuracy; switch to `gpt-4o-mini-transcribe` in Settings → Model when lower cost matters more.

## Modes

- **Prose** — natural sentences, capitalized, with terminal punctuation. Default for most apps. Uses digits for times, exact prices, measurements, and option labels (`$5`, `3 hours`, `1 TB`, `option 1`), while keeping approximate prices idiomatic (`a few hundred dollars`, not `a few $100`). Small ordinary counts remain words (`three apples`). Letter-spelled number output such as `F-I-F-T-Y feet` is normalized to `50 feet`. Very large number phrases stay as words when they cannot be converted safely. Empty short toggles are rejected before transcription.
- **Command** — shell-command formatting, including spoken punctuation, numbers, and suffix keys; no automatic capitalization or trailing period. Auto-selected when the focused app is a terminal (Terminal, iTerm, Wave, etc.).
Press your **Mode toggle** hotkey (default `⌃⌥M`) to switch directly between Always prose and Always command. Choose Auto again in Settings → Mode when you want app-based detection.

## Smart Cleanup and spoken edits

Enable **Smart cleanup** in Settings → Mode to apply spoken editing triggers and an optional gpt-4o-mini pass. The model may adjust punctuation and capitalization while preserving the words supplied to it. Vox rejects cleanup that adds, removes, or repeats words, increases the semicolon count, or adds a sentence beginning with “And”. Rejected or failed cleanup leaves the pre-cleanup text available for insertion.

Spoken edits run before the model: **scratch that** or **delete that** replaces the previous attempt, and **new paragraph** or **new line** inserts a break. In prose, use a separate sentence for a paragraph or line command. After an unfinished phrase, `scratch that, …` replaces that phrase back to the nearest clause boundary while retaining earlier context; a comma, dash, or ellipsis before the correction marks the unfinished phrase.

To bypass Smart Cleanup and spoken edits for one recording:

- Hold **Option while pressing your record hotkey** (Fn by default).
- Say **verbatim** or **literal** as the first word; Vox removes that prefix.

These shortcuts bypass cleanup. Normal mode formatting, dictionary substitutions, number normalization, and suffix keys still apply, so the inserted result can differ from raw speech-to-text output.

Personalization → **Custom Instructions** lets you save inline guidance or choose a Markdown style file. Vox reads a linked file fresh and sends it with eligible cleanup requests to OpenAI. The linked file must be UTF-8 text no larger than 256 KB. If it becomes unavailable, Vox uses the saved inline guidance; **Unlink** also returns to that fallback.

## Writing-voice skill

If you already have a writing-voice skill or Markdown style guide, link it under Personalization → **Custom Instructions**; there is no need to generate another one. If you do not have one, **Export Writing-Voice Skill…** creates a self-contained `SKILL.md` for use with Codex, Claude, or another instruction-aware application. The export infers style from attributable raw dictation transcripts before cleanup and uses final text only for raw-vs-final cleanup comparisons. It includes skill metadata, register guidance, observed cadence, cleanup preferences, composition prompts, final checks, and evidence boundaries. It does not include transcript excerpts and does not treat remote or unattributed meeting participants as evidence of your voice.

About 100 prose dictations can produce a rough first pass. For a relatively accurate guide, aim for roughly 500 prose dictations or 10,000–15,000 attributable words across professional, casual, technical, and reflective contexts. Variety matters as much as the raw count. Import the exported Markdown using the destination application's instructions or skill setup. Exporting does not automatically link the file back to Vox.

## Dictionary

Personalization → Dictionary lets you define custom substitutions:
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

Enable **Meeting Transcription (Beta) → Enable Meeting Mode** in Settings and acknowledge participant consent before recording. Vox transcribes meetings by capturing system audio (the people on
the call, mixed by Zoom/Meet/etc) and your local mic in parallel.

- Press the **Meeting hotkey** (default `⌃⌥⇧M`) to toggle the floating Meeting
  panel. Pick **Meeting** from the menu-bar dropdown or select the **Meeting**
  section in the Vox window to open the Meeting view and bring the panel
  forward.
- Click the **green Record disc** to start the session. Click the **red Stop square** to end it.
- Closing the panel with the `X` only hides the UI — recording continues.
  Re-open the panel via hotkey or menu to see the running timer or stop.
- Choose the provider under Settings → **Meeting Transcription (Beta)**. Deepgram Nova-3 uses a Deepgram API key, transcribes each captured source separately, and labels your microphone as You and remote voices with anonymous speaker labels; OpenAI Whisper uses your OpenAI key and separates your microphone (You) from system audio (Other).
- When you click Stop, Vox transcribes via the configured meeting provider,
  interleaves segments by time, and opens the transcript browser.
- Select a saved meeting and click **Copy Transcript** to put its plain-text
  transcript on the clipboard. Use **Export…** to save plain or timestamped text.
- Meeting audio is temporary and deleted after transcription and optional
  summarization finish. Raw provider segments, final displayed segments, and
  summaries are retained in authenticated encrypted transcript files.

### Permissions for Meetings

- **Screen Recording** — required for system-audio capture via ScreenCaptureKit.
- **Microphone** — required for the local-mic stream.
Grant both in System Settings → Privacy & Security.

### Auto-show meeting panel

Settings → Meeting Transcription (Beta) → **Auto-show meeting panel when a call starts**. When
on, Vox checks window titles every few seconds only when a supported meeting
app or browser is frontmost, and keeps watching after a meeting is detected.
It pops the floating panel as soon as a known meeting is detected:
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

Settings → Meeting Transcription (Beta) → **Generate meeting summary after transcription**
(default on). After Vox finishes transcribing, it sends the segments
to gpt-4o-mini and stores a markdown summary with key decisions and
action items. The summary appears at the top of the transcript browser
(click the **Summary** disclosure to expand). Summary requests send up to the first 60,000 transcript characters and are
billed separately by OpenAI; Vox's dictation usage estimate excludes them.
Without an OpenAI key or if summarization fails, the transcript remains available
without a summary.

### Quality tips

- Muting a microphone in your meeting app does not mute Vox's separate local
  capture. Check the microphone source before recording. Repeated or invented
  phrases can come from silence; Vox filters known patterns, but review the
  transcript before relying on it.
- Whisper invents filler phrases ("you", "thanks for watching", "subscribe")
  on silent leading audio. The OpenAI meeting path filters known patterns
  after transcription; silent meeting audio can still be uploaded.
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

## History and privacy

Dashboard → Home shows recent dictations. **Raw vs final** appears only when the original speech-to-text result differs from the final text; identical results have no disclosure. Audio is deleted after processing, so this comparison cannot establish what was actually spoken.

Dictation and meeting history are encrypted locally with a key in macOS Keychain. Settings → **Dictation history** controls dictation retention (Forever, 1 year, 90 days, or 30 days). Those choices do not delete saved meeting transcripts; delete meetings in the Meeting view when needed.

Dictation audio goes to OpenAI. Meeting audio goes to the selected transcription provider; optional summaries and Smart Cleanup send text to OpenAI. Local encryption does not control provider retention. The dictionary, style files, copied text, and exported meeting files remain ordinary readable data. Copying only encrypted history files to a different Mac does not copy their Keychain encryption key.

Settings → **Paste behavior** keeps the latest transcription on the clipboard by default. If you turn this off, Vox restores the previous clipboard text after local paste only when no other app has changed the clipboard. Remote insertion keeps the transcription on the clipboard because synchronization can take longer.

## Updates

Use the menu → **Check for Updates…**. Your saved settings and API keys remain in place. If hotkeys or paste stop working after an update, confirm Vox is enabled in both Input Monitoring and Accessibility, then quit and reopen it. Check Microphone and, for meetings, Screen Recording as needed. A real short dictation verifies that the updated app can record and insert text.

## Files

- Dictionary: `~/Library/Application Support/Vox/dictionary.json`
- Smart cleanup fallback: `~/Library/Application Support/Vox/cleanup-profile.md`; a linked external Markdown file replaces it while selected.
- Encrypted dictation history: `~/Library/Application Support/Vox/DictationHistory/history.enc`
- Temporary dictation recordings: `~/Library/Application Support/Vox/Recordings/`
- Encrypted meeting transcripts: `~/Library/Application Support/Vox/MeetingTranscripts/<id>/transcript.enc`
- Logs: `~/Library/Logs/vox.log`
- Auto-relaunch agent: `~/Library/LaunchAgents/com.andykumeda.vox.plist`

## Troubleshooting

- **Vox disappears after a crash** — launch it once from the app bundle. Vox
  installs a per-user LaunchAgent that restarts abnormal exits automatically.
- **Paste fails silently** — make sure Vox launched via `open /Applications/Vox.app`,
  not the binary directly. TCC attributes Accessibility permissions to the
  launching process.
- **Remote desktop paste fails** — Screen Sharing/VNC and Parsec try System
  Events text insertion first, then fall back to delayed clipboard sync plus
  remote Cmd+V and Unicode-backed physical typing. RustDesk uses delayed
  clipboard sync plus remote Cmd+V first, with the same physical typing
  fallback. Paste locks the target process and aborts if focus drifts (text
  stays on the clipboard).
- **Text appears slowly after recording** — check `~/Library/Logs/vox.log` for
  `dictation timing`, `transcription request model=...`,
  `transcription api key read elapsed=...`, and `transcription http attempt`
  lines. A slow first dictation after relaunch can be Keychain warming; longer
  waits after that usually mean the OpenAI transcription request or network path
  is slow. The `timeout=...` value scales up for longer WAVs, and
  `resource_timeout=...` is the remaining hard deadline shared by the request
  and any retry. Smart Cleanup can add a smaller second wait. Hold Option while
  pressing Fn, or start with "verbatim", to skip Smart Cleanup for one recording.
  Routine transcript diagnostics log character/word counts rather than transcript
  bodies; provider and system failures are also recorded as errors.
- **Wrong transcription plus delayed start/stop sounds** — pin the intended
  USB/studio mic under Settings → Microphone. Vox keeps that input as the macOS
  default while it runs, including across output changes, and fails safely if
  it is unavailable instead of switching to Bluetooth. An `inputFormat
  sampleRate=8000.0` log indicates a Bluetooth-route transition; Vox retries
  once when the hardware format changes during startup.
  Bluetooth output can still delay the cue while the speaker wakes.
- **Fn key doesn't fire** — confirm Vox has Input Monitoring and Accessibility
  access. If the Globe key opens another macOS action, set System Settings →
  Keyboard → "Press 🌐 key to" to **Do Nothing**. Restart Vox after changing
  permissions.
- **Wrong transcription on short phrases** — add a Dictionary entry to fix
  the specific misfire (e.g., spoken `-shell` → `-l`).
- **Meeting recording starts but mic is silent** — happens when another app
  (or a prior meeting session) left CoreAudio holding the input device.
  Quitting Vox + reselecting the input device in System Settings → Sound
  can help; restart Vox and verify a new recording afterward.
- **Dictation captures silence after a meeting** — check the selected microphone
  and its input level in System Settings → Sound. Vox restores a pinned input
  below 70% to 75% when the device supports software gain. Persistently silent
  captures can also indicate a route or permission problem; reselect the input,
  restart Vox, and verify a new short recording.
