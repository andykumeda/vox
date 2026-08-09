# Vox Handoff

Last updated: 2026-08-03

## Current state

- Project root: `/Users/andy/Dev/vox` on Mac mini `AKsMini`.
- Release: `0.7.29` build `48` is the last published cut; working tree has
  unreleased prose number-normalization improvements (not tagged/released).
- Branch: `main`.

## Unreleased: prose number contexts

- `NumberNormalizer` now converts small spelled-out numbers in quantitative
  contexts instead of leaving 1–9 as words:
  - currency: `five dollars` → `$5`, `fifty cents` → `50¢`
  - time: `three hours` → `3 hours`, `five o'clock` → `5 o'clock`
  - data sizes: `one terabyte` → `1 TB`
  - percent: `five percent` → `5%`
- Ordinary prose still keeps small counts as words (`three apples`).
- Whisper prose prompt tightened to prefer digits/symbols for these cases.
- `swift test`: 406 tests, 0 failures.

## Verification

- Local app refreshed 2026-08-03: `./scripts/build-app.sh` →
  `/Applications/Vox.app`, LaunchAgent restarted
  (`com.andykumeda.vox`). Still reports Info.plist `0.7.29` / build `48`
  (version not bumped; binary includes unreleased changes).
- Live smoke confirmed: prose currency / time / measurement number forms.

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
- Do not bump Info.plist / appcast / DMG unless cutting a release.
