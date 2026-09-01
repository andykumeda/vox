# Updating Vox

How to install a newer release of Vox over an existing install.

## Development production deployments

The Mac mini may run an unreleased production deployment for live validation.
Such a deployment must always use a new `CFBundleShortVersionString` and
`CFBundleVersion` that are higher/distinct from the latest public appcast item.
The current public identity is `0.7.38` build `58`; future unreleased builds
must use a newer identity. Do not reuse the public identity for changed code,
and do not add an unreleased build to the public appcast.

## In-app update (Sparkle, recommended)

Vox ships in-app updates via Sparkle. The appcast is served at
`https://andykumeda.github.io/vox/appcast.xml` and the daily auto-check
will surface new releases. To check on demand:

1. Click the menu-bar Vox icon → **Check for Updates…**.
2. Follow the prompt to download + install. Vox quits and relaunches itself.
3. If any integration stops working, **re-grant permissions** in System
   Settings → Privacy & Security:
   - **Input Monitoring** → enable Vox
   - **Accessibility** → enable Vox
   - **Microphone** → enable Vox
   - **Screen Recording** → enable Vox (only if you use Meeting transcription)

Your API key, hotkeys, dictionary, and settings persist — they're stored
in the Keychain and `~/Library/Preferences/com.andykumeda.vox.plist`,
both keyed on bundle ID, not signature.

## Why an update can require permissions again

Vox is not yet signed and notarized with an Apple Developer ID. Development and
release builds use the local self-signed `vox-dev` identity when it is available
and fall back to ad-hoc signing when it is not. macOS can invalidate TCC grants
when the installed bundle's signing requirement changes, when an ad-hoc build's
code hash changes, or after an OS/security update.

Result: permissions may survive an update, but callers must be prepared to
re-grant them. Vox can still launch while hotkeys, audio, paste, or meeting
capture remain unavailable.

Inspect the installed requirement with:

```sh
codesign -d -r- /Applications/Vox.app 2>&1
```

`TeamIdentifier=not set` alone does not distinguish an ad-hoc signature from
Vox's self-signed development certificate. A future Developer ID-notarized
release is the durable fix for update trust and permission churn.

## Manual fallback (if Sparkle fails)

Sparkle relies on:

- GitHub Pages serving the appcast at `andykumeda.github.io/vox/appcast.xml`.
- The repo being public so the DMG asset is anonymously downloadable.
- The bundled Sparkle EdDSA public key matching the signing private key.

If any of those break, fall back to manual install.

### TL;DR (manual)

1. Quit Vox from Activity Monitor, or run `killall vox` in Terminal.
2. Download the latest `Vox.dmg` from
   [Releases](https://github.com/andykumeda/vox/releases/latest).
3. Open the DMG, drag `Vox.app` into `/Applications`,
   replacing the previous copy.
4. Eject the DMG, launch Vox.
5. Re-grant permissions (same list as above).

### Scripted manual update (CLI)

```sh
# 1. Quit any running instance
killall vox 2>/dev/null

# 2. Download latest release DMG (requires `gh`)
gh release download --repo andykumeda/vox --pattern Vox.dmg --dir ~/Downloads --clobber

# 3. Mount, replace, eject
hdiutil attach ~/Downloads/Vox.dmg -nobrowse
rm -rf /Applications/Vox.app
ditto "/Volumes/Vox/Vox.app" /Applications/Vox.app
hdiutil detach /Volumes/Vox

# 4. Strip Gatekeeper quarantine and launch
xattr -dr com.apple.quarantine /Applications/Vox.app
open /Applications/Vox.app

# 5. Re-grant permissions
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"      # Input Monitoring
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"    # Accessibility
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"       # Microphone
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"    # Screen Recording (meetings only)
```

If the volume mounts as `/Volumes/Vox 1` (because a stale `/Volumes/Vox`
exists), adjust the path or eject the older one first with
`hdiutil detach /Volumes/Vox`.

## Verifying the update worked

```sh
# Bundle version
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  /Applications/Vox.app/Contents/Info.plist

# Process is the new bundle (not a stale one)
pgrep -fl vox

# Live log — hold Fn briefly, you should see a "Fn press" line
tail -f ~/Library/Logs/vox.log
```

If `Fn press` does not appear after holding Fn, **Input Monitoring** is
the most likely missing grant. The startup banner in `~/Library/Logs/vox.log`
shows `AXIsProcessTrusted=true/false` for Accessibility and `mic permission
granted=true/false` for Microphone — but it does **not** log Input
Monitoring status, so a missing IM grant is silent. Check the pane
manually.

## Troubleshooting

**Sparkle says "An error occurred in retrieving update information."**
Either GitHub Pages is disabled (re-enable in repo settings → Pages, source `main` / `/docs`) or the appcast hasn't propagated yet. Verify with:

```sh
curl -sI https://andykumeda.github.io/vox/appcast.xml | head
```

A 200 means it's live; a 404 means Pages is off.

**Sparkle downloads but install fails.** Check that the DMG asset is
anonymously downloadable:

```sh
curl -sIL https://github.com/andykumeda/vox/releases/download/v<version>/Vox.dmg | head
```

A 302 → S3 means it's reachable. A 404 means either the asset isn't
attached to the release or the repo is private.

**App launches but the menu bar icon doesn't appear.** Another instance
is already running from a different location. Run `pgrep -fl vox` and
`killall vox`, then relaunch.

**App appears in Input Monitoring but events still don't fire.** Toggle
it off and back on, then quit and relaunch Vox. macOS sometimes caches
a stale grant against an old `cdhash`.

**Fn key opens emoji picker instead of recording.** System Settings →
Keyboard → "Press 🌐 key to" → set to *Do Nothing*. Otherwise macOS
intercepts Fn before Vox sees it.

**You moved Vox.app to a new location.** Keep the development and release
installation at `/Applications/Vox.app`. LaunchServices and the per-user
LaunchAgent can otherwise continue referring to the prior bundle. Relaunch with
`open /Applications/Vox.app` or restart the LaunchAgent explicitly.
