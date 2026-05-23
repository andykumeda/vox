# Agent Instructions

## Project

Vox is a macOS Swift package/app for push-to-talk dictation and meeting transcription. It has several OS-integration surfaces that unit tests cannot fully cover: Accessibility, Input Monitoring, Microphone, Screen Recording, pasteboard timing, AppleScript/System Events, ScreenCaptureKit, Sparkle updates, and remote desktop clients.

## Workflow

- Read `HANDOFF.md` first when picking up work; it carries operational state and release caveats that may not belong in `README.md`.
- Use `rg`/`rg --files` for repo search.
- Keep edits scoped to the current task. Do not rewrite unrelated release history or stale design docs unless the task needs it.
- Do not commit until manual smoke is confirmed for changes involving paste, remote desktop insertion, TCC permissions, meeting capture, or Sparkle release behavior.
- Use `git commit --no-gpg-sign`; pinentry is unreliable in non-tty shells on this machine.
- Stage only intended files. Do not include `.build/`, `dist/`, `.worktrees/`, `tools/`, local logs, credentials, or generated junk.

## Verification

- Default Swift check: `swift test`.
- Dictation regression check: `./scripts/run-dictation-regression.sh`.
- App bundle check for local use: `./scripts/build-app.sh`, then relaunch `dist/Vox.app`.
- Release build/signing: `./scripts/make-dmg.sh` plus Sparkle `sign_update`; update `docs/appcast.xml` only when cutting a release.

## Documentation

- Update `HANDOFF.md` when current operational status, manual verification, known caveats, or next steps change.
- Update `README.md` and `Resources/help.md` for user-facing behavior changes.
- Keep `docs/remote-dictation-status.md` in sync with remote desktop paste behavior; that file exists to avoid re-debugging old VNC/RustDesk failure modes.

## Remote Paste Notes

- Screen Sharing/VNC, RustDesk, and Remote Control Mode are intentionally different insertion paths.
- Remote paste changes need live validation; unit tests can cover target selection and helper behavior, but not whether a remote client forwards modifiers, pasteboard state, or AppleScript events.
- Avoid describing all remote failures as "previous recording pasted." Recent failures have also included lost capitalization and `?` becoming `/` when synthetic Shift was dropped.

## Release Notes

- Sparkle release signing must happen on this Mac, where the EdDSA private key is installed.
- Ad-hoc-signed updates can require re-granting Mic, Input Monitoring, Accessibility, and Screen Recording permissions.
- Do not bump `Resources/Info.plist`, tag, edit `docs/appcast.xml`, or publish a DMG unless explicitly doing a release.
