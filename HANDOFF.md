# Vox Handoff

Last updated: 2026-07-28

## Current state

- Project root: `/Users/andy/Dev/vox` on Mac mini `AKsMini`.
- Release: `0.7.29` build `48`, tag `v0.7.29`, Sparkle appcast + GitHub
  Release DMG published (or publishing in this session).
- Branch: `main`.

## Changes in 0.7.29

- Remote paste locks frontmost pid/bundle; Screen Sharing AppleScript targets
  that unix id; focus drift aborts injection (transcript stays on clipboard).
- Remote physical fallbacks use Unicode-backed shifted characters; Remote
  Control Mode no longer overrides Screen Sharing / RustDesk / Parsec.
- Clipboard waits poll focus; paste vs Paste Last serialized; history `record`
  is synchronous.
- Meeting stop with nil recorder fails/clears; start aborts if session cleared
  mid-create; save failures logged; transport retry capped at 20 minutes.
- Removed obsolete `docs/superpowers/` docs; refreshed remote-dictation status.

## Verification

- `swift test`: 384 tests, 0 failures (pre-release).
- DMG codesigned with `vox-dev`; Sparkle `sign_update` signature in appcast.
- Live smoke on MacBook after Sparkle update still recommended (paste + TCC).

## MacBook update (Sparkle)

On the MacBook: menu bar → **Check for Updates…**, or wait for the daily check.
Re-grant Input Monitoring / Accessibility / Microphone / Screen Recording if
macOS prompts after the self-signed update.

## Signing notes

- Sparkle EdDSA private key and `vox-dev` codesign identity were available on
  `AKsMini` for this cut.
- Prefer Git push/pull between clones; do not put a live tree in iCloud Drive.
