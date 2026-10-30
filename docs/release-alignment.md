# Production release alignment

Owner: Codex. Requested 2026-10-30. Target: 0.7.81 / build 105.

Acceptance: installed production bundle, committed local/GitHub source, GitHub
release DMG, and public Sparkle appcast agree on version/build. Public download
must match the signed DMG, including signature and byte length. Preserve unrelated
audit/fallback work. Capture code is unchanged from 0.7.80, including the previously
local-only 0.7.79 early-release fix.

| Work | State | Evidence |
| --- | --- | --- |
| Align delivery rules | Verified | AGENTS.md, README, and UPDATING require a matching release for each production update unless the user explicitly requests local-only delivery |
| Tests and package | Verified | 526 macOS + 21 VoxCore tests pass; seven dictation fixtures quality 1.0/failure rate 0.0; DMG checksums, strict codesign and EdDSA against bundled public key pass |
| Local production install | Deployed | AKsMini installed/restarted 0.7.81/105, PID 1189; hotkey startup and mic permission pass; installed executable matches mounted DMG; prior signing requirement unchanged |
| GitHub and Sparkle publication | Deployed | Source 99f2ad5 and tag/release v0.7.81 pushed; appcast e346731; public DMG bytes match signed artifact; raw/live feed identity, URL, signature and length match; Pages 41097272279 passed |

Manual checks: actual Sparkle installation on a second Mac, live Fn/paste and USB
route cycling remain pending. Release verification does not prove those behaviors.
Rollback: publish a new higher version/build containing the last known good code;
do not overwrite published assets or reuse an identity. Prior releases stay available.

Final DMG SHA-256: `e30eea55ae57e5984e5b5f06d82d4468d1a27674a190fa486c6c39e7248e4ceb`,
2,774,940 bytes. Installed/DMG executable SHA-256:
`06664bd34a1cc8ea3d391bc90320eacda190d5f35bffc88e6e2c2bba2589eaaa`.
Existing Swift Sendable warnings remain. Initial sandboxed compiler/cache and
code-signing trust checks required rerunning outside the sandbox; final checks pass.

GitHub verification: source Dictation Regression `41097193603`, tag Release Gate
`41097235396`, appcast Dictation Regression `41097273830`, and Pages
`41097272279` all passed. The earlier source-only Pages run was superseded/cancelled
by the successful appcast deployment.
