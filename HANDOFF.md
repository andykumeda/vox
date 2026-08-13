# Vox Handoff

Last updated: 2026-08-12

## Current state

- Project root: `/Users/andy/Dev/vox` on Mac mini `AKsMini`.
- Release: `0.7.32` build `51` is the current published release. It includes
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
