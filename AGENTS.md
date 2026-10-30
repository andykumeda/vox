# Agent Instructions

## Project

Vox is a macOS Swift package/app for push-to-talk dictation and meeting transcription. It has several OS-integration surfaces that unit tests cannot fully cover: Accessibility, Input Monitoring, Microphone, Screen Recording, pasteboard timing, AppleScript/System Events, ScreenCaptureKit, Sparkle updates, and remote desktop clients.

## Workflow

- Read `HANDOFF.md` first when picking up work; it carries operational state and release caveats that may not belong in `README.md`.
- Use `rg`/`rg --files` for repo search.
- Keep edits scoped to the current task. Do not rewrite unrelated release history or stale design docs unless the task needs it.
- After every change, deploy the resulting state to production before handing it back. For Vox, the standard production deployment is `./scripts/build-app.sh` (which installs `/Applications/Vox.app`) followed by restarting `com.andykumeda.vox` with `launchctl kickstart -k "gui/$(id -u)/com.andykumeda.vox"`; verify the deployed app when the change affects runtime behavior.
- Every production deployment must have a new, unique bundle identity. Before deploying, bump both `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`; never deploy changed code while reusing the latest published version/build. Complete each production deployment as a coordinated release: the installed app, committed local/GitHub source, GitHub release DMG, and public Sparkle feed must agree on version/build before handoff. Local-only production builds require an explicit user exception; a successful local install alone is not completion.
- Fully document and commit every completed change before handing it back. Record pending manual smoke for paste, remote insertion, TCC, meeting capture, or Sparkle behavior accurately; pending smoke does not waive the commit requirement. Preserve unrelated work and stage only intended changes.
- Use `git commit --no-gpg-sign`; pinentry is unreliable in non-tty shells on this machine.
- Stage only intended files. Do not include `.build/`, `dist/`, `.worktrees/`, `tools/`, local logs, credentials, or generated junk.

## Verification

- Default Swift check: `swift test`.
- Dictation regression check: `./scripts/run-dictation-regression.sh`.
- App bundle check for local use: `./scripts/build-app.sh`, then restart the
  installed app with
  `launchctl kickstart -k "gui/$(id -u)/com.andykumeda.vox"` (or use
  `open /Applications/Vox.app` before its LaunchAgent exists).
- Release build/signing: `./scripts/make-dmg.sh` plus Sparkle `sign_update`; update `docs/appcast.xml` only when cutting a release.
- Every push of Vox changes must include a matching Sparkle release. A source-only push is incomplete: build/sign the DMG on AKsMini, publish the matching GitHub tag/release asset, update and push `docs/appcast.xml`, and verify the public feed and downloadable DMG match the version/build, signature, and byte length. Complete the release as one coordinated delivery; do not claim a push complete while Sparkle still advertises an older release. Production deployment remains required.
- A local production deployment is not allowed to reuse the public appcast's version/build. Check the newest `<sparkle:shortVersionString>` and `<sparkle:version>` in `docs/appcast.xml` before choosing the next identity.

## Documentation

- Update `HANDOFF.md` when current operational status, manual verification, known caveats, or next steps change.
- Update `README.md` and `Resources/help.md` for user-facing behavior changes.
- Keep `docs/remote-dictation-status.md` in sync with remote desktop paste behavior; that file exists to avoid re-debugging old VNC/RustDesk failure modes.

## Remote Paste Notes

- Screen Sharing/VNC, RustDesk, and Remote Control Mode are intentionally different insertion paths.
- Remote paste changes need live validation; unit tests can cover target selection and helper behavior, but not whether a remote client forwards modifiers, pasteboard state, or AppleScript events.
- Avoid describing all remote failures as "previous recording pasted." Recent failures have also included lost capitalization and `?` becoming `/` when synthetic Shift was dropped.

## Release Notes

- Sparkle release signing must happen on the Mac mini (`AKsMini`), where the
  EdDSA private key is installed. This remains true when an agent is running
  from a MacBook clone or Codex Desktop is displaying a remote mini workspace.
- Self-signed/non-notarized updates can require re-granting Mic, Input
  Monitoring, Accessibility, and Screen Recording permissions.
- A user-authorized push of Vox changes includes authorization for its required matching Sparkle release; no second approval is required for that delivery. A requested production update includes its matching source push and Sparkle release; do not leave a local-only production version ahead of GitHub or Sparkle unless the user explicitly requests that exception. Bump `Resources/Info.plist` for every changed production deployment and verify the signed release before publication.

## Operational configuration

- Do not hardcode operational or service configuration in application code: provider routing, API endpoints, model identifiers, prices or cost estimates, request budgets, retry policies, and service-specific language/options must be externally configurable through Settings, environment variables, or a documented configuration file.
- Keep defaults in one documented configuration source. Resolve overrides consistently, validate them, and expose the effective provider/configuration so users can understand where requests go. Do not duplicate defaults across clients or UI labels.
- Never silently fall back to another provider, endpoint, model, or credential when a configured service is unavailable. Report the failure or use an explicitly authorized fallback policy. Follow-provider settings must track the user's current provider selection.
- Keep secrets in the platform credential store or an explicitly supported secret source; never put credentials in checked-in defaults or logs.
- Protocol syntax, entitlements, bundle/app-group/Keychain identities, file-format constants, and tested algorithm invariants may remain implementation constants. Do not disguise a changeable service choice or operational policy as an implementation constant.
- When touching existing hardcoded operational configuration, move it into the shared configuration path and add focused verification for precedence, validation, and provider routing. Do not introduce speculative controls unrelated to the app's supported behavior.
