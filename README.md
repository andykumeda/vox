# Vox

Push-to-talk voice dictation for macOS (Apple Silicon). Hold **Fn**, speak, release — Vox transcribes via OpenAI and pastes at the cursor in whichever app has focus. Also includes a meeting-transcription mode (system audio + your mic in parallel), a personal dictionary, and an opt-in LLM cleanup pass.

For end-user instructions, read [Quick Help](Resources/help.md). For current deployment status, verified behavior, and outstanding manual checks, read [HANDOFF.md](HANDOFF.md) before changing the project. The [codebase audit ledger](docs/codebase-audit.md) records this review and unresolved findings.

Default transcription model is `gpt-4o-transcribe` for better dictation accuracy. Switchable to `gpt-4o-mini-transcribe` (lower cost) or `whisper-1`.

## iPhone MVP

The repository also contains an experimental iOS 18+ host app and custom
keyboard extension. It reuses Vox's transcription, silence gate, cleanup,
dictionary, and post-processing core. The host app owns microphone capture;
the keyboard requests a handoff and receives completed text through an App Group. Opening the host may require a
manual app switch. The exact Notes initiation, recording, and one-time insertion
flow remains an unverified physical-device gate. This is a focused personal /
TestFlight MVP with a bring-your-own OpenAI key. See
[Mobile/README.md](Mobile/README.md) for signing, installation, and physical
iPhone validation steps.

If text appears slowly after you release Fn, check `~/Library/Logs/vox.log`.
Vox logs `transcription http attempt` and `dictation timing` lines so you can
tell whether the wait is the OpenAI transcription request, Smart Cleanup, or
paste insertion. Long dictations get a larger transcription timeout budget than
short clips; the attempt log includes both the request timeout and the remaining
hard deadline shared by all retry attempts. Holding Option while pressing Fn
skips Smart Cleanup for that recording. Routine transcript diagnostics record character and word counts rather than
transcript bodies. Provider and system failures are also recorded as errors.

## Modes

Vox runs in one of two text-shaping modes:

- **Prose** — capitalizes sentence starts, ensures a space after `.`, `!`, `?`, detects questions, and synthesizes a Space keystroke for inter-sentence separation. Spelled-out quantities become digits in quantitative contexts (`five dollars` → `$5`, `three hours` → `3 hours`, `one terabyte` → `1 TB`, `option one` → `option 1`); letter-spelled numbers such as `F-I-F-T-Y feet` are also normalized (`50 feet`). Ordinary small counts stay words (`three apples`). Empty short toggles are rejected using sustained frame-level speech activity before transcription. Number phrases too large to convert safely stay as words, and sentence capitalization supports Unicode letters whose uppercase form expands to multiple characters.
- **Command** — no auto-capitalize, no trailing period, aggressive number-to-digit conversion, spoken-punctuation expansion (`dash`, `dot`, `pipe`), NATO phonetic letters after dashes, and trailing-keyword key-event synthesis (`tab`, `return`, `escape`, `control X`).

Mode is auto-selected by the frontmost app: terminals (`Terminal.app`, `iTerm2`, `Warp`, `Ghostty`, `Alacritty`, `kitty`, `WezTerm`, `Hyper`, `Wave`, `Tabby`) → command; everything else → prose. Override via Settings → Mode (`auto` / `always prose` / `always command`) or the **mode-toggle hotkey** (default `⌃⌥M`).

## Requirements

- macOS 13+ on Apple Silicon.
- Full Xcode 16+ selected with `xcode-select`. The standalone Command Line
  Tools package is not sufficient because it omits the SwiftUI macro plugin.
- An [OpenAI API key](https://platform.openai.com/api-keys).
- `git` (preinstalled on macOS).
- *Watch out:* if Homebrew OpenSSL 3 is on `PATH` ahead of `/usr/bin/openssl`, `create-dev-cert.sh` may fail with `MAC verification failed` during the PKCS#12 import. The script pins `/usr/bin/openssl` internally; if you still see it, run `which openssl`.

## Quick start

End-to-end from a fresh Mac:

```sh
# Install Xcode from the App Store, launch it once, then select it:
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
git clone https://github.com/andykumeda/vox.git
cd vox
./scripts/setup.sh
```

`setup.sh` is idempotent. It verifies a complete Xcode toolchain (including
SwiftUI macros), Swift, `/usr/bin/openssl`, the `security` CLI, and architecture;
uses an installed Apple team signing identity when available, otherwise
creates the `vox-dev` self-signed fallback if missing (prompts for **login
keychain password**); builds, installs, launches, and prints the permission
checklist.

Then:

1. Grant **Microphone**, **Input Monitoring**, **Accessibility** when macOS prompts (or in System Settings → Privacy & Security if a prompt was missed). Meeting transcription also needs **Screen Recording**.
2. Click the menu-bar Vox icon → **Settings** → paste OpenAI API key → **Save** → click **Always Allow** on the keychain prompt.
3. Hold **Fn**, speak, release.

## Developing on two Macs

Keep an independent local clone on each Mac rather than placing a live Git
working tree in iCloud Drive. SwiftPM's `.build` tree, Git metadata, symlinks,
and code-signing artifacts should stay on a local filesystem. Use Git to hand
work between machines, and edit a branch on only one Mac at a time:

```sh
# Before switching Macs
git status
swift test
git push

# On the other Mac
git fetch origin
git switch <branch>
git pull --ff-only
```

Finish the required live smoke before committing paste, remote insertion, TCC,
meeting-capture, or Sparkle changes. Avoid switching machines mid-change for
those surfaces. If an unavoidable uncommitted handoff is needed, transfer only
the source diff/untracked source files; never synchronize `.git`, `.build`,
`dist`, logs, or credentials through a cloud drive.

Run `./scripts/setup.sh` once on each Mac to select its signing identity and
establish its TCC grants. Prefer an Apple-issued team identity and keep the
installed app's signing requirement stable across rebuilds. Do not alternate
differently signed development bundles on one Mac. Official DMGs and Sparkle
signatures are produced only on the Mac mini
(`AKsMini`), where the Sparkle EdDSA key is installed.

Codex Desktop may run on one Mac while its project workspace executes on the
other. Confirm the execution host with `hostname` before building, installing,
or interpreting paths: commands affect the workspace host, not necessarily the
Mac displaying the Codex window.

## Updating

Vox ships in-app updates via **Sparkle**. Click the menu-bar icon → **Check for
Updates…**, or wait for the daily auto-check. Releases are not notarized;
current builds prefer an Apple-issued team identity, with self-signed and
ad-hoc development fallbacks. An update can require re-granting Microphone,
Input Monitoring, Accessibility, and Screen Recording. See
[docs/UPDATING.md](docs/UPDATING.md) for the manual fallback.

## Manual build

```sh
./scripts/create-dev-cert.sh   # fallback only when no Apple team identity exists
./scripts/build-app.sh
launchctl kickstart -k "gui/$(id -u)/com.andykumeda.vox"
# Before the LaunchAgent exists, use: open /Applications/Vox.app
```

`build-app.sh` prefers an installed Developer ID Application or Apple Development identity. Its stable Apple team identifier allows macOS Keychain authorization to persist across rebuilds. If neither exists, the script falls back to the self-signed `vox-dev` identity created by `create-dev-cert.sh`, then to ad-hoc signing. No signing mode guarantees TCC persistence. With the self-signed fallback, modern macOS may still ask for Keychain authorization after each changed build because it records a per-build code hash rather than a team identifier.

By default the script installs the signed build to `/Applications/Vox.app`; set `INSTALL_TO_APPLICATIONS=0` to only write `dist/Vox.app`.

Every installed production build must be distinguishable from the last public
release. Before running this deployment path, check the newest identity in
`docs/appcast.xml`, `Resources/Info.plist`, and the installed bundle; bump both
`CFBundleShortVersionString` and `CFBundleVersion` to a new, unique identity.
Never install changed code under a version/build already used by a public or
unreleased deployment.
For an unreleased local deployment, record the new identity in `HANDOFF.md`
but do not edit the Sparkle appcast or publish a DMG unless cutting a public
release.

On first app launch, Vox installs a per-user LaunchAgent at
`~/Library/LaunchAgents/com.andykumeda.vox.plist` and hands off to that
supervised process. If Vox crashes or exits abnormally later, launchd restarts
it automatically. **Quit Vox** exits normally and stays stopped. After replacing
an already-running bundle, restart the LaunchAgent so the process loads the new
executable; merely opening an installed app can leave the older process alive.

For an ordinary launch, use the app bundle rather than running the binary directly:

```sh
open /Applications/Vox.app
```

Running `./dist/Vox.app/Contents/MacOS/vox` from a shell makes the process a child of the terminal, and TCC attributes Accessibility grants to the terminal instead of Vox — paste silently fails.

## Hotkeys

Settings → Hotkeys lets you rebind:

| Hotkey | Default | Trigger | Purpose |
|---|---|---|---|
| Record dictation | `Fn` | press-and-hold | hold to record, release to transcribe + paste |
| Mode toggle | `⌃⌥M` | tap | switch directly between Always prose and Always command (skips `.auto`) |
| Meeting panel | `⌃⌥⇧M` | tap | toggles the floating Meeting Record/Stop panel |
| Paste last transcription | *(disabled)* | tap | re-pastes the most recent dictation. Pick a combo to enable. |

Press-and-hold can be flipped to **tap-toggle** for the record hotkey.

Hold **Option while pressing the record hotkey** to bypass Smart Cleanup and spoken editing triggers for that recording. Normal mode formatting, dictionary substitutions, and suffix keys still apply.

## Verbatim / literal

Two ways to bypass Smart Cleanup for a single dictation:

- **Hold Option + record hotkey** — skip Smart Cleanup and editing triggers.
- **Say "verbatim" or "literal" as the first word.** The prefix is stripped and Smart Cleanup and editing triggers are skipped.

Both controls bypass the cleanup stage, not the earlier mode formatting and
dictionary stage. Capitalization, punctuation, number normalization, dictionary
substitutions, and suffix-key detection can still change the provider text.
The original speech-to-text result is retained separately in dictation history.

## Settings

Click the menu-bar Vox icon → **Settings**. While Settings is selected, the Vox window raises above normal app windows so it does not get hidden behind a larger window:

- **OpenAI API key** — stored in the macOS Keychain (`com.andykumeda.vox` / `openai-api-key`). Click **Always Allow** on the keychain prompt the first time.
- **Model** — `gpt-4o-transcribe` (default), `gpt-4o-mini-transcribe`, or `whisper-1`. Vox estimates audio cost with bundled rates of $0.006/min, $0.003/min, and $0.006/min respectively; these are implementation estimates, not a live billing quote. Check [OpenAI pricing](https://openai.com/api/pricing/) for current charges.
- **Usage (lifetime)** — calls, audio minutes, words, USD estimate. Refresh + Reset buttons. Estimate = `audioMinutes × model.usdPerMinute`; this excludes cleanup, meeting summaries, and any separately billed output tokens.
- **Mode override** — `Auto (detect by app)` / `Always prose` / `Always command`. Prose uses symbols for exact prices (`five dollars` → `$5`) while preserving approximate ranges in conventional words (`a few hundred dollars`, not `a few $100`).
- **Smart cleanup** — opt-in LLM cleanup via gpt-4o-mini adjusts punctuation and capitalization in prose while preserving every dictated word. Cleanup does not increase the number of semicolons or sentence-initial “And” occurrences in its input. If the model adds, removes, or repeats wording, Vox discards that cleanup and uses the pre-cleanup transcription, preventing lost words and preventing questions or requests from becoming assistant answers. An explicit `scratch that, …` after an unfinished phrase replaces only that phrase back to the nearest clause boundary—even when the speech pause is transcribed as a comma, dash, or ellipsis—while the established sentence context remains. Personalization → **Custom Instructions** can use the inline `cleanup-profile.md` fallback or a linked Markdown file that is read fresh and sent to the configured OpenAI cleanup provider with each eligible dictation. Bypassed by verbatim modifier or "verbatim"/"literal" prefix word.
- **Meeting mode** — enable the meeting panel and Screen Recording capture. Includes a consent acknowledgement (you must inform participants before recording).
- **Recordings storage** — audio is temporary and deleted after dictation or meeting processing reaches a terminal state. A startup sweep removes crash leftovers.
- **Microphone** — choose **System Default** or pin Vox to a specific input device. A pinned device is made macOS's default and selected by its persistent Core Audio UID at launch and before every dictation; if it is disconnected, Vox fails safely instead of switching to another microphone. If another app leaves that microphone's writable macOS input level below 70%, Vox restores it to 75% before recording. Devices without a software volume control are left untouched.
- **Dictation history** — encrypted raw STT and final delivered text, with a **Raw vs final** disclosure when the texts differ and retention choices (forever / 1y / 90d / 30d). Prose transcription asks the STT provider for literal, non-interpretive speech; punctuation and formatting are handled afterward.
- **Writing-voice skill export** — Personalization → Custom Instructions exports an import-ready `SKILL.md` for Codex, Claude, or another instruction-aware app. It infers style from attributable raw dictation transcripts before cleanup, while using final text only for raw-vs-final cleanup patterns. It does not embed transcript bodies or treat remote meeting participants as the user's voice. Users who already have a writing-voice skill can simply link it instead. About 100 prose dictations gives a rough first pass; roughly 500 dictations or 10,000–15,000 words across varied contexts is the recommended target for a relatively accurate guide.
- **Paste behavior** → **Keep transcription on clipboard after paste** — on by default. When on, transcribed text remains on your clipboard so you can paste again if focus moved away. When off, prior clipboard text is restored ~1.5s after paste; restore is skipped if anything else writes to the clipboard in the meantime. Remote insertion paths skip restoring the prior clipboard because remote clipboard synchronization can lag behind the local paste event.
- **Sounds** — choose the macOS alert used for start recording, stop recording, and errors, or None to silence a cue. Preview each sound from Settings. Vox prepares the start cue silently after launch, then plays it before the microphone opens to reduce startup delay while keeping the cue audible; Bluetooth output can still take time to wake.
- **Hotkeys** — rebind any of the four hotkeys (see table above).

## Dictation troubleshooting

- **Wrong transcription with delayed start/stop sounds** — pin the intended USB/studio mic under Settings → Microphone. Vox then binds that device before every dictation and will not fall back to a Bluetooth input. In `~/Library/Logs/vox.log`, `AudioRecorder.start inputFormat sampleRate=8000.0` indicates a Bluetooth-route transition; Vox retries once if the hardware format changes during startup. Bluetooth output can still delay the audible cue while the speaker wakes.
- **Vox hears silence after a conferencing app** — some conferencing apps automatically adjust microphone gain and can leave the system input level very low afterward. For a pinned microphone with a writable volume control, Vox restores levels below 70% to 75% when recording starts; normal levels are preserved.
- **Text appears slowly after recording** — check `~/Library/Logs/vox.log` for `dictation timing`, `transcription request model=...`, `transcription api key read elapsed=...`, and `transcription http attempt` lines. A slow first dictation after relaunch can be Keychain warming; longer waits after that are usually the OpenAI transcription request, network path, or Smart Cleanup. The `timeout=...` value scales up for longer WAVs. `resource_timeout=...` is the remaining hard deadline shared by the request and any retry, so retries cannot multiply a stalled request into a much longer wait.
- **Raw-vs-final troubleshooting** — open Dashboard → Home and expand **Raw vs final** on a recent dictation when the texts differ. Equal entries intentionally have no disclosure. This compares the initial speech-to-text result with final output, not the recording with its transcription: Vox deletes the WAV after processing. Routine transcript diagnostics contain counts and timing, not transcript bodies.

## Dictionary

Personalization → **Dictionary** lets you define custom substitutions:

- Spoken `vox` → replacement `Vox` (proper-noun fix in prose).
- Spoken `next field` → replacement `next tab` to insert "next" + Tab key.
- Mode scope: command, prose, or both.
- "Match only at start" anchors to the first word of an utterance.

Dictionary saves create their storage folder on first use, including in the iOS App Group.

12 built-in fixups are active behind the scenes (e.g. `ls -shell` → `ls -l`). To silence one: **Reveal in Finder**, edit `dictionary.json`, set `"enabled": false`. Reloads automatically.

A replacement that ends with one of these words fires that key after pasting:

- `tab` — Tab (needs at least one preceding word)
- `return`, `enter`, `newline` — Return
- `escape`, `esc` — Esc
- `control X` — Ctrl+X (any letter)

## Meeting transcription

Enable **Meeting Transcription (Beta) → Enable Meeting Mode** in Settings and acknowledge participant consent before recording. Vox transcribes meetings by capturing **system audio** (Zoom/Meet/etc, via ScreenCaptureKit) and your **local mic** in parallel.

- Press the meeting hotkey (default `⌃⌥⇧M`) to toggle the floating panel. Pick **Meeting** from the menu bar or select the **Meeting** section in the Vox window to open the Meeting view and bring the floating panel forward.
- Click the green **Record** disc to start. Click the red **Stop** square to end.
- Closing the panel with `X` only hides the UI — recording continues. Re-open the panel via hotkey or menu to see the running timer or stop.
- On Stop, Vox transcribes via the configured provider:
  - **Deepgram Nova-3 (default if a Deepgram key is set)** — each captured source is submitted in a separate whole-meeting request and the resulting segments are aligned on the meeting timeline. The microphone is labeled `You`; diarization within the system and optional Phone/FaceTime streams produces anonymous `Speaker` labels. Vox preserves separate speaker-ID ranges for those remote sources.
  - **OpenAI Whisper (fallback)** — mic and system streams are chunked, transcribed independently, and tagged `You` (mic) vs `Other` (system). No within-stream speaker separation.
  Provider is selectable in Settings → Meeting Transcription (Beta). Add a Deepgram API key in Settings → Deepgram API key (Keychain account `deepgram-api-key`).
- Meeting audio is temporary and deleted after transcription and optional summarization finish. Raw provider segments, final displayed segments, and summaries remain in authenticated encrypted transcript files.
- Select a saved meeting to use **Copy Transcript** for clipboard-ready plain text, or **Export…** to save plain or timestamped text.
- The transcript browser exposes a raw-provider comparison when filtering or cleanup changed the delivered meeting transcript. Re-transcription from retained audio is intentionally unavailable.
- Meeting silence handling does not guarantee that silent streams are skipped before upload. The optional Phone/FaceTime loopback track is currently consumed only by the Deepgram path; the OpenAI path uses the mic and system tracks.

Permissions: **Screen Recording** (system audio + window-title polling for auto-detect), **Microphone** (local stream).

The mic recorder runs a per-second peak-power watchdog so a stalled OS-level audio input (Teams renegotiating, USB power management, exclusive-access contention) self-recovers. After 30 s of consecutive floor-level silence the watchdog tears down the recorder, archives the part-file, and starts a fresh one writing to the original output URL. At stop, parts are concatenated via AVMutableComposition into a single m4a so the chunking pipeline is unchanged.

### Auto-show panel when a call starts (opt-in)

Settings → Meeting Transcription (Beta) → **Auto-show meeting panel when a call starts**. Vox checks window titles every few seconds only when a supported meeting app or browser is frontmost, and keeps watching after a meeting is detected. It pops the floating Meeting panel as soon as it sees a known meeting in progress:

- Teams desktop (`Meeting in`, `Meeting with`, `Meeting compact view`, `Call with`, `(Meeting)`)
- Zoom desktop (`Zoom Meeting`, `Zoom Webinar`)
- Webex desktop (`Webex Meeting`, `Webex Personal Room`)
- Slack huddle, Discord voice/video, Skype call
- Web meetings: Google Meet, Zoom web, Webex web, Teams web (active tab in Chrome / Safari / Edge / Arc / Brave / Firefox)

Recording is **never** auto-started — the user still clicks Record on the panel. Detection requires Screen Recording permission so `CGWindowListCopyWindowInfo` can return window titles. To debug detection, run `swift scripts/dump-windows.swift` from terminal (note: terminal-launched scripts will see empty titles unless you grant Terminal Screen Recording too).

### Meeting summary (opt-out)

Settings → Meeting Transcription (Beta) → **Generate meeting summary after transcription** (default ON). After Vox finishes transcribing, segments are sent to gpt-4o-mini with a structured prompt; the markdown summary (Summary / Key decisions / Action items) is stored on the transcript and rendered in a disclosure section at the top of the transcript browser. Summary requests are billed separately by OpenAI and are excluded from Vox's dictation usage estimate. At most the first 60,000 transcript characters are submitted. If the OpenAI API key is missing or the call fails, the summary is skipped and the transcript remains available.

## Menu bar icon

| State | Icon | Color |
|---|---|---|
| Idle (prose) | chrome-V on squircle | cyan/teal |
| Idle (command/terminal) | chrome-V on squircle | amber/gold |
| Recording | V with red dot badge | — |
| Transcribing | V with orange dot badge, pulsing | — |
| Meeting recording | filled record circle | red, pulsing |
| Meeting transcribing | waveform circle | orange, pulsing |
| Error | exclamationmark.triangle | template |

The orange macOS recording indicator dot also appears whenever Vox holds the mic — that's a system privacy feature.

The status menu contains **Dashboard**, **Meeting**, **Paste Last Transcription**, **Settings**, **Check for Updates…**, **Help**, and **Quit Vox**. Dashboard opens the Home view. Paste-last is disabled when no history exists and ignored while dictation is busy.

Remote desktop apps need special paste handling. When Vox is running on the Mac with the VNC/Parsec/RustDesk viewer frontmost, Screen Sharing/VNC and Parsec try System Events text insertion first, then fall back to delayed clipboard sync plus remote Cmd+V and Unicode-backed physical typing. RustDesk uses delayed clipboard sync plus remote Cmd+V first, with the same physical typing fallback. Paste locks the frontmost process at start and aborts if focus drifts (transcript stays on the clipboard). Paste Last Transcription uses the same async target-specific path. Overlapping completed dictations are not guaranteed to serialize their paste operations; keep the destination stable and verify consecutive insertions. Remote-dictation history and caveats are tracked in [docs/remote-dictation-status.md](docs/remote-dictation-status.md).

## Privacy and local data

Dictation audio is sent to OpenAI. Meeting audio is sent to the selected OpenAI
or Deepgram provider; optional summaries send meeting text to OpenAI. Smart
Cleanup sends the processed dictation, dictionary guidance, and active style
instructions to OpenAI. Local history encryption does not change provider
processing or retention.

Transcript history uses authenticated AES-256-GCM encryption with a per-install
key in Keychain. Copying only the encrypted files to another Mac does not
transfer that key. Dictionary and style files, exported text, clipboard contents,
and diagnostics are not encrypted by the transcript store. Exported meeting
text is readable by whichever application receives it.

## Files

- Dictionary: `~/Library/Application Support/Vox/dictionary.json`
- Smart cleanup profile fallback: `~/Library/Application Support/Vox/cleanup-profile.md`; a user-selected external Markdown file can replace it while linked. If the linked file is unreadable, Vox uses the inline fallback. Linked files must be UTF-8 and no larger than 256 KB.
- Encrypted dictation history: `~/Library/Application Support/Vox/DictationHistory/history.enc`
- Temporary dictation recordings: `~/Library/Application Support/Vox/Recordings/` (empty after terminal processing/startup recovery)
- Encrypted meeting transcripts: `~/Library/Application Support/Vox/MeetingTranscripts/<id>/transcript.enc` (audio is temporary)
- Logs: `~/Library/Logs/vox.log`

## Log file

```sh
tail -f ~/Library/Logs/vox.log
```

Lines include Fn press/release, AVAudioEngine state, WAV byte counts/RMS/duration,
request timing, transcript character/word counts, suffix-key counts, cost
estimate, hallucination-guard metrics, and meeting lifecycle. Dictated text and
meeting window titles are deliberately excluded from new log entries.

## Project layout

```text
Package.swift            macOS app + VoxCore library; Swift 6 tools, Swift 5 language mode
Resources/               Bundle metadata, entitlements, icons, bundled Quick Help
scripts/                 Setup, signing/build/install, icon and DMG generation, regression runner
Sources/AudioTapShim/    Objective-C exception boundary for audio tap installation
Sources/VoxCore/
  Audio/                 Portable WAV metrics
  Dictation/             Shared iOS transcription/post-processing pipeline
  Dictionary/            Entries, defaults, matching, persistence
  History/, Meeting/     Portable transcript data and raw/final comparisons
  Mobile/                UUID-scoped keyboard handoff state
  STT/                   OpenAI transcription, silence/hallucination guards, modes
  Text/                  Formatting, numbers, cleanup, dictionary protection, suffix keys
  Security/, Logging/    Keychain, transcript encryption, diagnostics
  Package.swift          Standalone local package consumed by the iOS project
Sources/vox/
  App/                   macOS menu, dashboard, settings, dictionary, Help, meeting UI, launch/update integration
  Audio/                 Core Audio input selection and AVAudioEngine WAV recording
  Context/, Hotkey/      Foreground-app mode detection and configurable global hotkeys
  Meeting/               System/mic/process capture, silence trimming, detection, summaries
  STT/                   Deepgram and OpenAI meeting transcription/chunking
  Text/                  TextInjector and target-specific paste paths
  Util/                  macOS preferences, history, temporary audio, usage, sounds, writing style
  VoxCoreExports.swift   Compatibility import for shared types
Mobile/                  iOS host app, keyboard extension, App Group support, Xcode project
Tests/voxTests/          macOS and shared-core regression coverage
Tests/VoxCoreTests/      Portable pipeline, encryption, and handoff coverage
HANDOFF.md               Current operational status and historical release evidence
docs/codebase-audit.md    Review scope, evidence, and unresolved findings
docs/UPDATING.md          End-user updates and signing/permission recovery
docs/dictation-regression.md  Fixture budgets and CI scope
docs/remote-dictation-status.md  Remote insertion paths and manual gates
docs/realtime-typing-next-phase.md  Deferred inline-typing design
docs/appcast.xml         Public Sparkle feed, changed only when releasing
docs/index.html          GitHub Pages landing page
```

## Testing

```sh
swift test
```

Focused dictation post-processing regression with enforced test budgets:

```sh
./scripts/run-dictation-regression.sh
```

See [docs/dictation-regression.md](docs/dictation-regression.md) for thresholds and CI scope. Unit tests do not verify macOS permissions, actual microphone capture, paste delivery, remote clients, or Sparkle installation; those require a live smoke on the affected Mac. iOS build and device gates are documented in [Mobile/README.md](Mobile/README.md).

## Releasing

The Sparkle EdDSA private key for signing updates lives only on the Mac mini
(`AKsMini`). Releases must be cut there, even when development happened on the
MacBook.

Before staging a release, inspect both `git diff` and `git status --short`.
Stage an explicit allowlist of source, test, and documentation files; do not
use `git add -A` in a worktree that may contain another task's changes. Keep
Xcode user state, `.build/`, `dist/`, logs, credentials, and runtime data out
of the release commit. A previous release attempt accidentally staged the
entire accumulated worktree, which made the release scope ambiguous and was
stopped before commit.

Before publishing a Sparkle update, compare the candidate bundle's code-signing
requirement with the currently installed release using the commands in
`docs/UPDATING.md`. Treat a changed certificate authority, TeamIdentifier, or
designated requirement as a release gate because macOS may invalidate Vox's
Accessibility and Input Monitoring grants. After installation, perform a real
Fn recording smoke on each target Mac and verify the `Fn press`, cue, recording,
transcription, and paste log entries before calling the update complete.

```sh
# 1. Bump CFBundleShortVersionString + CFBundleVersion in Resources/Info.plist.
#    These values must be newer than the latest appcast item, even for an
#    unreleased production deployment; never reuse a public version/build.
# 2. Build + sign DMG
./scripts/make-dmg.sh
.build/artifacts/sparkle/Sparkle/bin/sign_update dist/Vox.dmg
# → prints sparkle:edSignature="…" length="…"

# 3. Add a new <item> to docs/appcast.xml at the top, with the signature/length above
# 4. Commit, tag, push
git add Resources/Info.plist docs/appcast.xml
git commit --no-gpg-sign -m "release: 0.X.Y — …"
git tag v0.X.Y
git push origin main && git push origin v0.X.Y

# 5. Publish GitHub release with the DMG attached
gh release create v0.X.Y --title "Vox 0.X.Y" --notes "…" dist/Vox.dmg
```

GitHub Pages serves `docs/appcast.xml` at `https://andykumeda.github.io/vox/appcast.xml` (the `SUFeedURL` in `Info.plist`). Pages must remain enabled — disabling it breaks Sparkle for every existing install.

DMG asset URL is `https://github.com/andykumeda/vox/releases/download/v<version>/Vox.dmg`. The repo must remain **public** for anonymous Sparkle download; private repos block unauthenticated asset fetches.

### First-launch on another Mac (no Sparkle)

The DMG is not notarized. Gatekeeper may prevent the first launch even when
the app has an Apple Development signature. After downloading the intended
release, attempt to open `/Applications/Vox.app`, then use **Open Anyway** in
System Settings → Privacy & Security if macOS offers it. Grant the requested
permissions and verify an actual dictation on that Mac.

## Roadmap (not yet)

- SSH-vs-local detection inside a terminal
- Real-time inline typing — explicitly deferred; see [the next-phase design](docs/realtime-typing-next-phase.md)
- Separate mode for code editors
- Floating HUD near the cursor
- Homebrew cask
- Developer ID-signed, notarized releases (reduces distribution friction; TCC persistence still requires verification)
- Per-call output token cost tracking (currently estimate is audio-only)
- Mission Control space-switcher via synthesized arrow keystrokes (not verified; signing/notarization alone is not a demonstrated fix)
