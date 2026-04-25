# Handoff: Vox install troubleshooting on second Mac

This file is for a fresh Claude session running in `~/Dev/vox` on Andy's
secondary Mac (user `kumedaa`, hostname `D09JW32R61`). Read it once,
then act.

> Note: the user prefers terse, fragment-style responses (caveman mode).
> Drop articles, pleasantries, hedging. Code blocks unchanged.

## What Vox is

macOS Apple-Silicon push-to-talk dictation app. Hold Fn → record → Groq
`whisper-large-v3` → paste at cursor. Two modes (prose / command,
chosen by frontmost-app bundle ID). Menu-bar app
(`LSUIElement=true`), no Dock icon. Repo:
[github.com/andykumeda/vox](https://github.com/andykumeda/vox).

Full docs in `README.md`. Don't repeat them — read on demand.

## Current symptom on this Mac

User can't launch Vox.app from Finder after copying to
`~/Applications/`. Symptoms gathered so far:

```text
$ /Users/kumedaa/Applications/Vox.app/Contents/MacOS/vox
2026-04-24T23:36:32.974Z [vox] hotkey.start() -> true
2026-04-24T23:36:32.992Z [vox] AXIsProcessTrusted=false
2026-04-24T23:36:34.940Z [vox] mic permission granted=true
^C
$ spctl -a -vv ~/Applications/Vox.app
~/Applications/Vox.app: rejected
$ codesign -dvv ~/Applications/Vox.app | head
…
CodeDirectory v=20500 size=1043 flags=0x10002(adhoc,runtime) hashes=22+7
Signature=adhoc
TeamIdentifier=not set
```

Diagnosis:
- App **does** run when launched directly (binary path in Terminal).
- `Signature=adhoc` ⇒ build fell back to ad-hoc instead of signing
  with `vox-dev`. That's why Gatekeeper rejects Finder launches AND
  why TCC permissions don't persist across rebuilds.
- `AXIsProcessTrusted=false` is downstream — even after granting
  Accessibility, a fresh ad-hoc rebuild invalidates it.

## Likely root cause

`scripts/build-app.sh` probes for the `vox-dev` signing identity. If
it doesn't find one it falls back to ad-hoc. On this Mac one of two
things happened:

1. **`vox-dev` was never installed** — `scripts/create-dev-cert.sh`
   wasn't run, or it failed silently.
2. **Cert installed but probe didn't see it.** Earlier versions of
   the script were broken by `set -o pipefail` + `grep -q` SIGPIPE
   (fixed in `843280a..HEAD` — see `git log scripts/build-app.sh`).
   If they built before pulling the fix, they got an ad-hoc binary
   and the cached app reflects that.

### Actual root cause found on 2026-04-24 session

Both of the above were red herrings on this MDM-managed Mac.
The real failure mode is two-layered:

1. **`find-identity -v` filters out untrusted self-signed certs.**
   Without a System-keychain trust root (which MDM prevents writing),
   the cert lists as `CSSMERR_TP_NOT_TRUSTED` and `-v` filters it.
   The old probe `security find-identity -v | grep '"vox-dev"'`
   therefore returns nothing → ad-hoc fallback, even with a perfectly
   usable private key sitting in the login keychain.
2. **`create-dev-cert.sh` only cleaned the login keychain.** Prior
   runs that *did* manage to add System-keychain trust left stale
   certs there. Seven accumulated on this Mac. That made
   `codesign --sign vox-dev` ambiguous.

Fix (committed this session):
- `build-app.sh` now probes `security find-identity ~/Library/Keychains/login.keychain-db`
  (no `-v`) and signs by SHA-1 hash — unambiguous, works whether
  the cert is System-trusted or not.
- `create-dev-cert.sh` now sweeps System-keychain duplicates
  (best-effort with cached sudo).

If you land fresh on this Mac and see adhoc output from `build-app.sh`
despite `vox-dev` existing in `~/Library/Keychains/login.keychain-db`,
you have an old build script. Pull.

## What to do — in order

### 1. Pull latest

```sh
cd ~/Dev/vox
git pull
```

### 2. Check identity state

```sh
security find-identity -v -p codesigning
security find-identity -v
```

Look for the line `... "vox-dev"`. It may show in **either** output
(some Macs only list it under `-p codesigning`). The build script
already merges both.

If `vox-dev` is **missing** from both → go to step 3.
If `vox-dev` is **present** → go to step 4.

### 3. Create the identity (only if missing)

```sh
./scripts/create-dev-cert.sh
```

The trust step is best-effort and silently skipped if `sudo` isn't
already cached (this user is on an MDM-managed Mac without admin).
That's fine — codesign doesn't need trust, only the private key in
the login keychain.

Re-run step 2 to confirm `vox-dev` now shows.

### 4. Rebuild and verify the signature

```sh
rm -rf build/ dist/
./scripts/build-app.sh
codesign -dvv build/Vox.app | grep -E "Authority|Signature|adhoc"
```

The `build-app.sh` output **must** contain
`→ codesign (vox-dev — permissions will persist)`.
The `codesign -dvv` output **must** contain `Authority=vox-dev` and
**must not** contain `adhoc`. If it still says ad-hoc, debug the
identity probe:

```sh
bash -x scripts/build-app.sh 2>&1 | grep -E "find-identity|IDENTITIES|SIGN_IDENTITY|codesign" | head
```

Check that the captured `IDENTITIES` string contains `"vox-dev"`. If
not, something is keeping `find-identity` from listing it. Inspect
`~/Library/Keychains/login.keychain-db` for the cert and key.

### 5. Replace the cached install and re-grant TCC

```sh
pkill -f "Vox.app/Contents/MacOS/vox" || true
rm -rf ~/Applications/Vox.app
cp -R build/Vox.app ~/Applications/
tccutil reset All com.andykumeda.vox
open ~/Applications/Vox.app
```

`tccutil reset` clears stale TCC entries that point at the old ad-hoc
identity. macOS will prompt fresh for Microphone, Input Monitoring,
and Accessibility. Grant all three. Subsequent rebuilds keep
permissions because the `vox-dev` signing identity is stable.

### 6. Functional smoke test

Watch the log live:

```sh
tail -f ~/Library/Logs/vox.log
```

Then hold **Fn** for ~2 s and speak. You should see a sequence like:

```
[vox] Fn press
[vox] Fn release
[vox] wav bytes=... duration=...s rms=... mode=prose
[vox] groq raw=...
[vox] processed=...
```

`AXIsProcessTrusted=true` should appear on next launch (after the
Accessibility grant). If it stays `false`, see *Known gotchas* below.

## Known gotchas (don't relearn the hard way)

- **Always launch via `open`, not by running the binary directly.**
  Direct invocation makes Vox a child of the Terminal process and TCC
  attributes Accessibility grants to the terminal, so Cmd+V paste
  silently fails. Direct binary invocation is fine for one-shot
  diagnostic runs (you'll see stderr) — just don't expect paste to
  work that way.
- **Fn key may not fire** if "Press 🌐 key to" is set to anything
  other than *Do Nothing* in System Settings → Keyboard. macOS
  intercepts before our `CGEventTap` sees it.
- **First-time Groq API key save** triggers a Keychain prompt. Click
  **Always Allow** (not "Allow") — otherwise it re-prompts every
  launch.
- **Self-relocator** triggers when running from `/Volumes/*` (mounted
  DMG) or `~/Downloads/*`. Running from `~/Applications/*` or
  `/Applications/*` is silent. If user is testing from
  `~/Dev/vox/build/Vox.app`, no dialog should fire.
- **MDM-managed Mac**: this Mac can't write
  `/Library/Keychains/System.keychain` even with sudo. Don't try.
  User-domain trust isn't accepted by codesign for "valid" filtering,
  but the key in the login keychain is enough to sign with.
- **Pipefail + grep -q** killed the earlier identity probe (see fix
  in commit before `Add self-relocator…`). If you ever rewrite the
  probe, use an intermediate variable:
  `IDS=$(security find-identity ...); echo "$IDS" | grep -q vox-dev`.

## Files you'll touch

| Path | Why |
|---|---|
| `scripts/build-app.sh` | Identity probe + ad-hoc fallback decision |
| `scripts/create-dev-cert.sh` | Generates `vox-dev` self-signed cert |
| `scripts/make-dmg.sh` | DMG packaging (used for distribution, not local install) |
| `Sources/vox/App/Relocator.swift` | "Move to /Applications?" dialog + AppleScript admin escalation |
| `Sources/vox/App/MenuBarController.swift` | `dlog()` to stderr + `~/Library/Logs/vox.log` |
| `Resources/Info.plist` | Bundle ID `com.andykumeda.vox`, `LSUIElement`, mic usage description |
| `Resources/vox.entitlements` | Audio input + AppleEvents (no sandbox) |
| `~/Library/Logs/vox.log` | Persistent log — `tail -f` while testing |

## After you fix it

If the change required a code edit, push it:

```sh
git add -A
git commit -m "..."
git push
```

The user is `andykumeda`; SSH auth works. The remote is `origin/main`.
No PR workflow — push straight to `main`.

If everything just needed configuration (no code change), update this
HANDOFF.md with what fixed it before signing off.
