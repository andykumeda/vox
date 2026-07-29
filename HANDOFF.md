# Vox Handoff

Last updated: 2026-07-28

## Current state

- Project root: `/Users/andy/Dev/vox`.
- Version: `0.7.29` build `48` (Info.plist bumped; no Sparkle appcast/DMG/tag
  yet — install via local `build-app.sh` on each Mac).
- Branch: `main` with paste/meeting durability hardening committed as 0.7.29.

## Changes in 0.7.29

- **Paste:** Lock frontmost pid/bundle at paste start; Screen Sharing AppleScript
  targets that unix id; abort on focus drift (leave transcript on clipboard).
- **Paste:** Remote physical fallbacks use Unicode-backed shifted characters
  instead of Caps Lock mangling; Remote Control Mode no longer overrides
  Screen Sharing / RustDesk / Parsec viewer paths.
- **Paste:** Clipboard sync waits poll focus; Screen Sharing avoids redundant
  pasteboard rewrite; Send Clipboard failure policy is wired; dictation paste
  and Paste Last are serialized.
- **Meetings:** `stop()` with nil recorder fails/clears instead of stuck
  `.chunking`; `start()` aborts if session cleared during recorder create;
  incremental saves log failures instead of `try?`; transport retry capped at
  20 minutes wall-clock.
- **History:** `DictationHistoryStore.record` is synchronous and returns success.
- **Docs:** Removed obsolete `docs/superpowers/` plans/specs. Updated
  `docs/remote-dictation-status.md`, `README.md`, `Resources/help.md`.

## Verification

- `swift test`: 384 tests, 0 failures.
- Remote paste and meeting capture still need live smoke after install.

## MacBook update path (no Sparkle publish)

On the MacBook, after pulling this commit:

```sh
cd ~/Dev/vox
git pull
./scripts/build-app.sh
launchctl kickstart -k "gui/$(id -u)/com.andykumeda.vox"
```

Or `open /Applications/Vox.app` if the LaunchAgent is not installed yet.

## Two-Mac / signing notes

- Prefer Git push/pull between independent local clones; do not put a live tree
  in iCloud Drive.
- Sparkle EdDSA release signing remains Mac-mini-only (`AKsMini`). Do not edit
  `docs/appcast.xml` or publish a DMG until cutting a signed release there.
- Self-signed updates can require re-granting Mic, Input Monitoring,
  Accessibility, and Screen Recording.

## Next steps

1. Push `main`, pull on MacBook, `build-app.sh`, smoke paste + meeting stop.
2. Optional later: cut Sparkle 0.7.29 on the mini (DMG + `sign_update` + appcast).
