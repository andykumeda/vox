# Updating Vox

How to install a newer release of Vox over an existing install.

## In-app update (Sparkle, recommended)

Vox ships in-app updates via Sparkle. The appcast is served at
`https://andykumeda.github.io/vox/appcast.xml` and the daily auto-check
will surface new releases. To check on demand:

1. Click the menu-bar Vox icon → **Check for Updates…**.
2. Follow the prompt to download + install. Vox quits and relaunches itself.
3. **Re-grant permissions** in System Settings → Privacy & Security:
   - **Input Monitoring** → enable Vox
   - **Accessibility** → enable Vox
   - **Microphone** → enable Vox
   - **Screen Recording** → enable Vox (only if you use Meeting transcription)

Your API key, hotkeys, dictionary, and settings persist — they're stored
in the Keychain and `~/Library/Preferences/com.andykumeda.vox.plist`,
both keyed on bundle ID, not signature.

## Why permissions break on every update

The release `Vox.dmg` is **ad-hoc signed** — there is no paid Apple
Developer ID in the release pipeline yet. macOS TCC (the privacy
database that gates Microphone, Accessibility, Input Monitoring, and
Screen Recording) keys its grants on the bundle's `cdhash`, which
changes on every rebuild for ad-hoc-signed apps.

Result: each new release looks like a "different" app to TCC, so prior
grants do not transfer. The app launches normally but hotkeys do not
fire and no audio is captured until you re-grant.

You can confirm a build is ad-hoc signed with:

```sh
codesign -dv /Applications/Vox.app 2>&1 | grep TeamIdentifier
# TeamIdentifier=not set    ← ad-hoc
```

A future release with a Developer ID certificate will keep `cdhash`
stable and TCC grants will persist across updates.

## Manual fallback (if Sparkle fails)

Sparkle relies on:

- GitHub Pages serving the appcast at `andykumeda.github.io/vox/appcast.xml`.
- The repo being public so the DMG asset is anonymously downloadable.
- The bundled Sparkle EdDSA public key matching the signing private key.

If any of those break, fall back to manual install.

### TL;DR (manual)

1. Quit Vox (menu bar icon → **Quit Vox**).
2. Download the latest `Vox.dmg` from
   [Releases](https://github.com/andykumeda/vox/releases/latest).
3. Open the DMG, drag `Vox.app` into `/Applications` (or `~/Applications`),
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
rm -rf ~/Applications/Vox.app           # or /Applications/Vox.app
cp -R "/Volumes/Vox/Vox.app" ~/Applications/
hdiutil detach /Volumes/Vox

# 4. Strip Gatekeeper quarantine and launch
xattr -dr com.apple.quarantine ~/Applications/Vox.app
open ~/Applications/Vox.app

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
defaults read /Applications/Vox.app/Contents/Info.plist CFBundleShortVersionString

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

**You moved Vox.app to a new location.** TCC grants are keyed on
`cdhash`, not path, so moving the bundle is fine. But LaunchServices may
still launch the old path if it remembers it — use
`open /full/path/to/Vox.app` to be explicit.
