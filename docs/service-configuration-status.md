# Service configuration status

## Scope and acceptance

Remove fixed operational service choices from request clients and UI. Keep supported defaults in `Sources/VoxCore/Configuration/service-defaults.json`; resolve environment overrides before saved Settings before defaults. Endpoints, models, provider routing, request budgets, service options, and audio price estimates must be configurable. Cleanup and summary default to Follow dictation provider and support explicit overrides without hidden provider fallback. Meeting audio remains explicitly Deepgram or OpenAI Whisper because its response contracts differ.

Protocol syntax, entitlements, persistent bundle/app-group/Keychain identities, and tested audio/text algorithm constants remain implementation contracts.

## Workstreams

| Workstream | Owner | State | Acceptance and verification |
|---|---|---|---|
| Global and repository policy | Configuration audit agent | Verified | Operational configuration rules added to `/Users/andy/Dev/AGENTS.md`, `/Users/andy/.codex/AGENTS.md`, and repository `AGENTS.md`; files inspected after edits. |
| Shared service configuration and routing | Primary agent | Verified | Central defaults, validated overrides, provider-correct credentials, no hidden OpenAI calls when following OpenRouter; Configuration, routing, validation, no-fallback, and safe meeting chunk-count tests pass. Final `swift test`: 496 macOS + 17 VoxCore tests, zero failures. |
| Settings controls and labels | Primary agent | Verified | Editable service fields and independent follow-provider choices; labels show effective routing and restart requirements; SwiftUI compilation passes, rendered editing smoke remains pending. |
| User documentation | Configuration audit agent | Verified | README and Quick Help describe intended configuration precedence and routing; reconcile with final implementation before verification. |
| Integration and production install | Primary agent | Deployed | Swift tests, dictation regression, unique bundle version/build, build/install/restart, installed identity/signature and runtime startup checks. |

## Deployment and remaining live checks

Installed/restarted Mini as unreleased **0.7.74 / 98** with PID 60337. Strict deep code-sign verification passes; packaged and installed executable SHA-256 both equal `dd4e6a2465176679023b4e2cbd84b7d1b584ea98cb079303a8e6f405b325001b`. Required service resource is present in the installed bundle; startup confirms mic permission, hotkey, selected audio input, and Accessibility. Mini retains OpenRouter; absent cleanup/summary overrides follow it. User requested the push with matching Sparkle release; publication is complete. Manual spoken dictation/cleanup, summary routing, Settings editing, and OS insertion behavior require live verification after installation; do not claim those checks from unit tests alone.

Generic iOS build passed after mobile provider routing, separate credentials, shared service controls, and invalid-selection checks. Physical-device installation and smoke remain unverified.

Final dictation regression passed: seven fixtures, quality 1.0, failure rate 0.0. `git diff --check` passes. Final release build/install/restart succeeded for unreleased 0.7.74 / 98; subsequent user-authorized Sparkle publication is complete.

Completion policy updated: all completed changes require full documentation and a focused commit; pending smoke must be recorded rather than used to skip committing. Vox pushes require a matching signed DMG/GitHub release/appcast and public verification. Global `/Users/andy/.codex/AGENTS.md` and `/Users/andy/Dev/AGENTS.md` are outside Git; Vox’s tracked instruction update is committed locally. The instruction-only update was initially local; the later explicit push request authorized matching Sparkle publication. Pre-existing local handoff/audit/fallback notes remain excluded.

Public delivery authorized: source commits `4e9c6f6` and `6c49493`, tag `v0.7.74`, signed/mounted verified DMG SHA-256 `9af03cd50b9f8e5bdb7650a4e3be23e56a7c5da5ba8e89828c8c560a5ffeb658`. Appcast 0.7.74 / 98 prepared with matching signature/length; GitHub release is published and anonymous public DMG SHA-256 matches. Raw/live appcasts verify identity, URL, signature, and length; GitHub Pages `38093759410`, source Dictation Regression `38093725799`, and Release Gate `38093727131` passed. Appcast-head regression `38093759671` also passed.
