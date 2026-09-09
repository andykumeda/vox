# Vox Handoff

Last updated: 2026-09-09

## Released 0.7.45 build 69: pin dictation and remove recording delays

- Settings now lists live Core Audio input devices and can persistently pin
  dictation to one device UID. Before every recording, Vox explicitly binds the
  engine to that device. If the pinned mic is disconnected, Vox reports an
  error rather than silently falling back to another input.
- This fixes a reproduced AT2020 USB / OontZ Bluetooth race. Playing the start
  cue woke the 44.1 kHz Bluetooth output; the input node briefly reported the
  Bluetooth mic at 8 kHz before Core Audio restored the 48 kHz USB input. The
  resulting tap/hardware mismatch failed engine startup with `-10868`.
- The first deployed iteration proved that device binding alone was
  insufficient: `AVAudioEngine` kept a stale 44.1 kHz graph after binding the
  48 kHz AT2020. The pinned path now reads the selected device's authoritative
  nominal sample rate and channel count directly from Core Audio and applies
  that exact format to the input tap, as required by `AVAudioInputNode`.
- Every visible Settings control was traced to its runtime consumer. Stale
  mode/meeting hotkey descriptions were corrected, the meeting-only Screen
  Recording permission was clarified, and cached controls now reload their
  persisted values whenever Settings reappears.
- Unpinned recorder startup still detects a native-format transition, rebuilds
  the converter and tap, and retries once. A failed start no longer makes the
  Fn hotkey permanently inert; the error state accepts a fresh attempt.
- A live first-recording trace showed the initial start cue blocking for 3.221
  seconds while the Bluetooth output woke; later starts reached the recorder in
  18-116 ms. Vox now prepares the configured start cue on a background queue at
  launch and reuses that prepared player for the first Fn press, while retaining
  cue-before-microphone ordering.
- A second live press arrived while the first recording was still in Smart
  Cleanup and was silently rejected by the `.transcribing` menu state. Dictation
  capture can now restart immediately while earlier pipelines continue; each
  pipeline retains its own mode/verbatim state, and an older completion cannot
  overwrite the icon state of a newer recording.
- The menu now ends with **Quit Vox**. A normal quit exits successfully, so the
  crash-only LaunchAgent does not reopen the app.
- Repeated Keychain prompts were reproduced and traced to all three Vox items:
  transcript encryption during startup recovery, OpenAI during background
  warmup, and Deepgram when Settings evaluated the meeting provider. Despite
  choosing **Always Allow**, the self-signed `vox-dev` app accumulated only
  per-build `cdhash:` partitions (156, 63, and 12 historical hashes) and no
  stable team partition. The build now prefers an Apple-issued team identity;
  a signed throwaway probe confirmed macOS records `teamid:852LS98PQ9`.
  Team-signed build 68 required one targeted Accessibility/Input Monitoring
  reset and re-grant, then relaunched with all three Keychain reads immediate
  and no password prompts.
- Focused regressions cover pinned selection order, unavailable-device refusal,
  8-to-48 kHz startup recovery, preference persistence, and error-state retry.
- Verification: `swift test` passes 459 macOS tests plus 11 VoxCore tests;
  `./scripts/run-dictation-regression.sh` passes with quality score `1.0` and
  failure rate `0.0`. The initial `0.7.43` / build `63` deployment confirmed the
  stale 44.1/48 kHz graph failure. Build 66 then passed a live four-recording
  sequence, including presses while older Smart Cleanup pipelines were still
  active, with the AT2020USB-X pinned and Bluetooth output active. Team-signed
  build 68 also passed two immediate recordings with the second capture opening
  while the first pipeline was still active; a subsequent quit/relaunch had no
  Keychain prompts and retained hotkey, Accessibility, and microphone access.
  Build 69 then changed the executable CDHash again and launched with Keychain
  warmup in 6 ms, `AXIsProcessTrusted=true`, microphone granted, and the hotkey
  listener active. All three Keychain items contain `teamid:852LS98PQ9`.
- Release verification: the installed and packaged executables match SHA-256
  `07581378b30f3955b30c2f9bd1ae11a1ca1823819cc8088322f314b22d35a6ff`;
  nested `codesign --verify --deep --strict` passes; `hdiutil verify` passes;
  the 2,670,909-byte DMG verifies against Sparkle EdDSA signature
  `Af6hRyAV7Tn2bhuophNhsV8TFt8ocFLrZebF8ALSOqgHasA8aOaRzkoySqwurzJtaCJEq/D31ixRD6bfsnNfCw==`.
- `0.7.45` / build `69` is the public Sparkle release replacing `0.7.38` /
  build `58`.

## Unreleased 0.7.42 build 62: exact symbol substitutions and meeting transcript copy/export

- Standalone symbol-only dictionary substitutions now remain exact in prose.
  In particular, Whisper's `Tilde.` output becomes the configured `~` rather
  than inheriting or regaining a sentence period. Inline uses still preserve
  normal sentence punctuation, such as `Use tilde.` becoming `Use ~.`.
- The selected-meeting toolbar now has a prominent **Copy Transcript** action
  for clipboard-ready plain text. The existing plain and timestamped file
  exports remain available under the clearer **Export…** menu.
- Verification: the focused regressions pass, and `swift test` passed 451
  macOS tests plus 11 VoxCore tests with dictation-regression quality score
  `1.0` and failure rate `0.0`. A later standalone regression-script run was
  blocked by unrelated in-progress tests added to the worktree after that clean
  run (`MenuBarControllerTests` expects a source member not yet present); those
  files are preserved and excluded from this batch.
- Live UI smoke on the initial build confirmed the Copy Transcript and Export…
  controls against a saved meeting: copy produced a non-empty 25,003-byte
  clipboard value, both export formats appeared, and Plain Text opened the
  native Save panel (cancelled without writing a file). That first `0.7.41` /
  build `61` install also picked up unrelated in-progress source edits that
  arrived in the shared worktree before compilation, so it was superseded by a
  clean isolated build from commit `bc32c82`.
- `./scripts/build-app.sh` built and installed `0.7.42` / build `62` from an
  isolated worktree at `bc32c82`. The installed executable matches that build's
  SHA-256 (`e16b3b07a100d75fdc9aabd153e0bdbca5f8c5c6721a6c52cef0da3e0de172b6`),
  and launchd is running the installed app. Public Sparkle remains `0.7.38` /
  build `58`.

## Unreleased 0.7.40 build 60: preserve dictated capability requests

- A live dictation asking to create a cover letter PDF was transcribed correctly,
  but Smart Cleanup interpreted it as a prompt and replaced it with "I'm unable
  to create PDFs or downloadable files." The assistant-response guard recognized
  several refusals but did not recognize the "I'm unable to ..." capability form.
- Cleanup now rejects that response form and fails open to the dictated text. The
  guard still permits the same wording when it was itself dictated.
- Regression coverage reproduces the cover-letter request and assistant refusal.
- Verification: `swift test` passes 446 macOS tests plus 11 VoxCore tests;
  `DictationRegressionTests` passes with quality score `1.0` and failure rate
  `0.0`. `./scripts/build-app.sh` installed the new identity, the installed and
  built binaries have matching SHA-256 hashes, and the LaunchAgent is running
  `/Applications/Vox.app/Contents/MacOS/vox`. The live cover-letter dictation
  was repeated successfully, confirming the deployed fix.
- `0.7.40` / build `60` is an unreleased local deployment; public Sparkle remains
  `0.7.38` / build `58`.

## Unreleased 0.7.39 build 59: restore start-recording cue and make sounds configurable

- Start recording played `Tink` *after* `AVAudioEngine` began capture. macOS
  mutes system sounds while an input stream is running, so the start cue was
  silent even though `NSSound.play()` returned true; the stop cue still worked
  because it plays after `recorder.stop()`. The start cue now plays before the
  mic opens, and `SoundPlayer` loads an independent copy from
  `/System/Library/Sounds` instead of stopping the shared `NSSound(named:)`
  cache.
- Settings → Sounds lets the user pick start, stop, and error alerts from the
  built-in macOS sounds (or None), with a preview button.
- Verification: `swift test` passes 445 macOS tests plus 11 VoxCore tests.
  Manual Fn start/stop smoke is required after the deployed build is used.
- `0.7.39` / build `59` is an unreleased local deployment; public Sparkle
  remains `0.7.38` / build `58`. `./scripts/build-app.sh` installed that
  identity and the LaunchAgent was restarted.

## Released 0.7.38 build 58: prevent input-format tap crashes and improve start cues

- AudioRecorder now installs its input tap with the node's live native format
  (`format: nil`) instead of a format queried before installation. This avoids
  AVAudioEngine's uncaught Objective-C format-mismatch exception during device
  renegotiation; recent crashes showed 8 kHz, 44.1 kHz, and 48 kHz inputs.
- SoundPlayer retains the active NSSound and falls back to the system beep when
  a named cue is unavailable, so successful recording starts have a reliable
  audible cue. A start that fails before engine startup still emits the error
  cue rather than the start cue.
- Verification: `swift test` passes 438 macOS tests plus 11 VoxCore tests.
  Manual hotkey/audio smoke remains required after the deployed build is used.
- Public Sparkle release: `0.7.38` / build `58`; the signed DMG, GitHub release,
  and appcast use this identity.
- Release cleanup note: an initial `git add -A` staged the accumulated Mobile,
  VoxCore, UI, tests, and docs work together with the audio fix. The commit was
  correctly refused because that broad staged set had not been explicitly
  reconciled. Future releases must inspect and stage an allowlist; local Xcode
  user state is excluded and remains untracked.

## Unreleased 0.7.37 build 57: import-ready personal writing-voice skill

- Replaced the brief statistical writing-style export with a self-contained
  `SKILL.md` intended for Codex, Claude, and other instruction-aware apps. It
  includes skill metadata, trigger scope, before-composing rules, professional,
  casual, spoken, and reflective registers, sentence and punctuation guidance,
  raw-vs-final cleanup observations, purpose-specific structures, reusable
  prompts, final checks, and evidence boundaries.
- The guide uses only attributable user text: prose dictations and explicitly
  local-mic meeting segments. Command dictations and remote or legacy
  unattributed meeting speech are excluded so another participant's language
  cannot be learned as the user's voice. Transcript excerpts are never copied
  into the export.
- Personalization explains that users who already have a writing-voice skill can
  link it instead of generating another. The UI and Help provide a practical
  sample guideline: about 100 prose dictations for a rough first pass, and about
  500 prose dictations or 10,000–15,000 attributable words across varied
  contexts for a relatively accurate guide.
- Verification: `swift test` passes 438 macOS tests plus 11 VoxCore tests;
  `./scripts/run-dictation-regression.sh` passes with quality score `1.0` and
  failure rate `0.0`. `./scripts/build-app.sh` installed `0.7.37` / build `57`,
  the LaunchAgent is running that identity, and the installed binary matches the
  built binary. A live save-panel smoke exported a 210-line, 1,700-word skill
  from retained history with valid frontmatter, all intended guide sections,
  no transcript excerpts, and explicit exclusion of remote/unattributed meeting
  speech; the temporary test export was removed afterward. Public Sparkle
  remains `0.7.34` / build `54`.

## Unreleased 0.7.36 build 56: encrypted transcript history and ephemeral audio

- Dictation and meeting transcript files now use authenticated AES-256-GCM
  encryption with a per-install key stored in macOS/iOS Keychain. Existing
  plaintext JSON is deleted only after the encrypted replacement decrypts and
  decodes successfully.
- Dictation history retains exact raw STT plus final delivered text; meeting
  history retains raw provider segments, final segments, and summaries. The UI
  exposes raw-vs-final comparisons without retaining audio.
- Dictation WAVs and every meeting audio artifact are deleted after terminal
  processing; startup recovers interrupted sessions and removes crash leftovers.
- Personalization can link a security-scoped Markdown style file that is read
  and sent to the configured OpenAI cleanup provider for every eligible request.
  Writing-style export derives an import-ready `SKILL.md` for Codex, Claude,
  or another instruction-aware app without copying transcript bodies into the
  file. Remote/unattributed meeting speech is excluded from voice evidence.
- Security review hardened Keychain failures and concurrent first-use creation,
  verifies encrypted candidates before replacing the prior store, retries
  deletion of leftover plaintext, and sweeps orphan meeting audio without
  depending on successful transcript decryption.
- Settings navigation now logs its source, starts on Home, and accepts only
  explicit menu/sidebar routes. This hardens the path associated with reports
  of Settings appearing during later dictations; live recurrence monitoring is
  still required because the original popup was not deterministically reproduced.
- Verification completed: `swift test` passes 436 macOS tests plus 11 VoxCore
  tests; `./scripts/run-dictation-regression.sh` passes with quality score `1.0`
  and failure rate `0.0`; and the generic iOS 18 device build succeeds without
  code signing. The independent security review's high/medium findings were
  fixed and covered by focused migration/orphan-audio tests.
- `./scripts/build-app.sh` installed unreleased `0.7.36` / build `56`, and the
  LaunchAgent is running that identity. Live migration produced one encrypted
  dictation envelope and 63 encrypted meeting envelopes, with zero plaintext
  history files remaining. Startup removed 2,046 dictation WAVs and all meeting
  M4A/chunk artifacts; post-launch counts are zero.
- Manual spoken dictation/paste, a real meeting capture, linked-file panel flow,
  style export save-panel flow, and multi-recording Settings-popup monitoring
  remain unconfirmed. Do not commit until those privacy and OS-integration smoke
  tests pass. Public Sparkle remains 0.7.34 / build 54.

### Speech-to-text provider to revisit

- Google recently introduced `gemini-3.5-transcribe`, a dedicated transcription
  model with automatic language detection, custom vocabulary, word-level
  timestamps, speaker diarization, and smart formatting. Google's current
  estimate is approximately `$0.005` per audio minute including estimated text
  output, compared with the approximately `$0.006` per minute documented for
  Vox's default `gpt-4o-transcribe`.
- This is a benchmark candidate, not yet a confirmed replacement. Compare it
  with `gpt-4o-transcribe` on representative private dictation and meeting
  samples, measuring names, technical terms, numbers, punctuation, latency,
  diarization, and actual cost.
- The Google API still receives the audio. Confirm the paid/free-tier data-use
  setting and provider-retention behavior before enabling it as a default in a
  privacy-focused build. If selected, preserve the raw provider result before
  cleanup so the existing raw-versus-final history remains meaningful.

## Unreleased 0.7.35 build 55: iPhone MVP and shared VoxCore

- Added an iOS 18+ host app and `Vox Keyboard` extension under `Mobile/`. The
  host app owns microphone capture, API credentials, transcription, cleanup,
  history, and dictionary editing; the keyboard remains a normal QWERTY
  keyboard and exchanges only scoped request state and completed text through
  `group.com.andykumeda.vox`.
- Added a UUID-scoped, persisted `MobileDictationExchange` state machine. It
  rejects stale transitions, consumes a matching result once, and expires
  insertable results after two minutes so an older transcript cannot appear in
  a newer field.
- Extracted portable transcription, silence gating, text shaping, cleanup,
  dictionary, keychain, and logging code into `VoxCore`. The existing macOS
  executable imports that module through a compatibility export, while the iOS
  project consumes it as a local Swift package.
- Generic iOS device build succeeds without code signing. Physical-device
  install, the host-app launch from the keyboard, background transcription,
  insertion across third-party apps, Full Access behavior, and secure-field
  fallback remain mandatory manual checks. This host currently has an Xcode 27
  beta CoreDevice/CoreSimulator service-version mismatch, so it could not
  discover a simulator or attached iPhone during this work.
- Verification: `swift test` passes 423 macOS tests plus 8 VoxCore tests;
  `./scripts/run-dictation-regression.sh` passes with quality score `1.0` and
  failure rate `0.0`. `0.7.35` / build `55` is an unreleased local deployment;
  the public appcast remains `0.7.34` / build `54`.

## Released in 0.7.34: preserve dictated wording and honor profile triggers

- Smart Cleanup now fails open when its LLM response adds more than two words
  beyond the transcription, preventing an interpretation from replacing the
  dictated text.
- Profile syntax such as `Additional trigger: “rather”, “or rather”` is wired
  into deterministic correction handling. Comma-joined `scratch that` phrases
  now remove the prior attempt while preserving the replacement clause.
- Public Sparkle release: `0.7.34` / build `54`; appcast and GitHub release use
  this identity.

## Released in 0.7.34: empty-toggle transcription guard

- Dictation clips now require sustained frame-level speech activity in addition to duration and aggregate RMS, regardless of total clip length. This blocks empty record-button toggles whose handling noise has deceptively high average RMS while preserving clips with sustained voice activity.
- Regression coverage includes the observed `0.742625s` / RMS `590` empty-toggle case and a voiced short-clip allow case.
- The release includes the frame-level speech-activity gate from build `53`.

## Current state

- Project root: `/Users/andy/Dev/vox` on Mac mini `AKsMini`.
- Release: `0.7.34` build `54` is the current published release. It includes
  silent-dictation suppression, numeric normalization for measurements and
  option labels, and the deployment-identity safeguards.
- Branch: `main`.

## Unreleased: compact status menu

- The menu-bar dropdown now contains exactly Dashboard, Meeting, Paste Last
  Transcription, Settings, Check for Updates, and Help.
- The version header, Dictionary shortcut, Remote Control Mode toggle, Ignore
  Record Hotkey toggle, separators, and Quit command were removed from the
  dropdown. Dictionary remains under Personalization; the two persisted remote
  compatibility preferences and their underlying behavior remain unchanged.
- `swift test`: 413 tests, 0 failures.
- `./scripts/build-app.sh`: release build, signing, and installation succeeded;
  known pre-existing Swift 6 Sendable warnings remain.

## Released in 0.7.32: dictation correctness

- Empty or silent dictation holds suppress known invented filler instead of
  pasting it.
- Letter-separated number output such as `F-I-F-T-Y feet` becomes `50 feet`.
- Option labels such as `option one` become `option 1`; ordinary small-number
  prose remains unchanged.
- The transcription prompt and postprocessor both require numeric formatting
  in quantitative contexts.
- The production bundle is `0.7.32` build `51`; the public appcast and GitHub
  release use the same identity.

## Previously released in 0.7.30: prose number contexts

- `NumberNormalizer` now converts small spelled-out numbers in quantitative
  contexts instead of leaving 1–9 as words:
  - currency: `five dollars` → `$5`, `fifty cents` → `50¢`
  - time: `three hours` → `3 hours`, `five o'clock` → `5 o'clock`
  - data sizes: `one terabyte` → `1 TB`
  - percent: `five percent` → `5%`
- Ordinary prose still keeps small counts as words (`three apples`).
- Whisper prose prompt tightened to prefer digits/symbols for these cases.
- `swift test`: 412 tests, 0 failures.

## Verification

- Pre-release local app refreshed 2026-08-03: `./scripts/build-app.sh` →
  `/Applications/Vox.app`, LaunchAgent restarted
  (`com.andykumeda.vox`). Still reports Info.plist `0.7.29` / build `48`
  (version not bumped; binary includes unreleased changes).
- Live smoke confirmed: prose currency / time / measurement number forms.
- Release verification: silent-dictation filler suppression includes “The cat
  is on the mat.”; prose normalization converts letter-spelled number words and
  option labels (`option one` → `option 1`) to digits. Targeted tests and the
  dictation regression gate pass; live empty-hold and spoken-number smoke remain
  useful follow-up validation.
- Release artifact validation on 2026-08-09: `dist/Vox.app` passed strict deep
  code-signature verification; `dist/Vox.dmg` passed `hdiutil verify`; Sparkle
  EdDSA signature and appcast enclosure length were generated on `AKsMini`.

## CPU investigation (2026-08-08)

- The linked live investigation found `WindowServer` at ~140–148% CPU and
  Control Center at ~12–23%; Vox itself was ~7% before the fix and 0% after
  settling. The load persisted with Vox stopped, so Vox was not the sustained
  system-wide CPU consumer.
- The affected install had `autoShowMeetingPanel = 1`. Vox's sample showed
  the opt-in `MeetingDetector` repeatedly calling
  `CGWindowListCopyWindowInfo` / `SLWindowListCopyWindowInfo` while the user
  was in unrelated apps. The detector now skips that WindowServer query unless
  a supported meeting app/browser is frontmost, while continuing to inspect
  windows after a meeting has been detected.
- Installed and restarted `/Applications/Vox.app` with this fix. Full
  `swift test`: 409 tests, 0 failures. WindowServer remained high after Vox
  was stopped and after Control Center was restarted; this remaining issue is
  an OS/display compositor problem and may require logging out/rebooting,
  disconnecting the Brio/external display, or disabling display/video effects.

## Signing notes

- Sparkle EdDSA private key and `vox-dev` codesign identity live on `AKsMini`.
- Prefer Git push/pull between clones; do not put a live tree in iCloud Drive.
- The `0.7.32` / build `51` DMG is signed and published in the appcast. Future
  production deployments must use a new unique bundle identity before install.
