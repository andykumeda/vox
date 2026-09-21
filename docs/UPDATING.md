# Updating Vox

How to install a newer release of Vox over an existing install.

## Development production deployments

A development Mac may run an unreleased production deployment for live validation.
Such a deployment must always use a new `CFBundleShortVersionString` and
`CFBundleVersion` that are higher/distinct from the latest public appcast item.
Check `docs/appcast.xml`, `Resources/Info.plist`, and the installed bundle
before choosing the next identity. Do not reuse any prior public or unreleased
identity for changed code, and do not add an unreleased build to the public
appcast. Record the current deployment and its verification in `HANDOFF.md`.
After `./scripts/build-app.sh`, restart the installed app with:

```sh
launchctl kickstart -k "gui/$(id -u)/com.andykumeda.vox"
# On the first launch, before the agent exists:
# open /Applications/Vox.app
```

An installed bundle version alone does not prove the running process loaded it.

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

API keys remain in Keychain, hotkeys and preferences in
`~/Library/Preferences/com.andykumeda.vox.plist`, and dictionary, style fallback,
and encrypted history in `~/Library/Application Support/Vox/`. macOS privacy grants are
different: Accessibility and Input Monitoring are tied to the installed code
identity and designated signing requirement, so a signed update can leave Vox
listed as a new client even when the bundle ID is unchanged.

## Why an update can require permissions again

Public releases are not yet Developer ID-notarized. Builds prefer
an installed Developer ID Application or Apple Development identity so macOS
Keychain records a stable team partition. Without an Apple team identity, the
build falls back to the local self-signed `vox-dev` identity, then ad-hoc
signing. Modern macOS records `vox-dev` as a per-build code-hash partition, so
even **Always Allow** can prompt again after every changed build. macOS can also
invalidate TCC grants when the installed bundle's signing requirement changes,
when an ad-hoc build's code hash changes, or after an OS/security update.

Result: permissions may survive an update, but callers must be prepared to
re-grant them. Vox can still launch while hotkeys, audio, paste, or meeting
capture remain unavailable. Treat a signing identity change as a release
blocker until it has been deliberately reviewed and live-tested on every
supported Mac.

Inspect the installed requirement with:

```sh
codesign -d -r- /Applications/Vox.app 2>&1
```

Before publishing a Sparkle update, compare the current installed app with the
candidate bundle on the release Mac:

```sh
codesign -d -r- /Applications/Vox.app > /tmp/vox-installed-requirement.txt 2>&1
codesign -d -r- dist/Vox.app > /tmp/vox-candidate-requirement.txt 2>&1
diff -u /tmp/vox-installed-requirement.txt /tmp/vox-candidate-requirement.txt
```

Review any change to the certificate authority, TeamIdentifier, or designated
requirement before publishing. A changed requirement can invalidate existing
Accessibility and Input Monitoring grants. After installing the candidate via
Sparkle on each target Mac, verify the version, confirm Vox appears in both
trust lists, and complete a real Fn recording that produces the start cue,
stop cue, recording log entry, transcription, and paste.

`TeamIdentifier=not set` alone does not distinguish an ad-hoc signature from
Vox's self-signed development certificate. An Apple Development identity
provides stable local team trust; a future Developer ID-notarized release is
still the intended distribution improvement. It does not guarantee that macOS
will preserve every permission across updates.

## Manual fallback (if Sparkle fails)

Sparkle relies on:

- GitHub Pages serving the appcast at `andykumeda.github.io/vox/appcast.xml`.
- The repo being public so the DMG asset is anonymously downloadable.
- The bundled Sparkle EdDSA public key matching the signing private key.

If any of those break, fall back to manual install.

### Manual install

1. Stop any active recording and choose **Quit Vox** from its menu. Do not
   force-kill the supervised process: its LaunchAgent can restart abnormal exits.
2. Download the latest `Vox.dmg` from
   [Releases](https://github.com/andykumeda/vox/releases/latest).
3. Open the DMG, drag `Vox.app` into `/Applications`,
   replacing the previous copy.
4. Eject the DMG, launch Vox.
5. Re-grant any missing permissions and verify an actual dictation (same list
   as above).

### Scripted manual update (CLI)

```sh
# Run after stopping recordings and choosing Quit Vox from the Vox menu.
# 1. Unload supervision while replacing the bundle; no job on a first install is OK.
launchctl bootout "gui/$(id -u)/com.andykumeda.vox" 2>/dev/null || true

# 2. Download the latest release DMG (requires gh)
gh release download --repo andykumeda/vox --pattern Vox.dmg --dir ~/Downloads --clobber
hdiutil verify ~/Downloads/Vox.dmg

# 3. Mount, verify, replace, eject. Use the actual mount path if it differs.
hdiutil attach ~/Downloads/Vox.dmg -nobrowse
codesign --verify --deep --strict "/Volumes/Vox/Vox.app"
# Remove the old bundle only after the downloaded bundle verifies.
rm -rf /Applications/Vox.app
ditto "/Volumes/Vox/Vox.app" /Applications/Vox.app
hdiutil detach /Volumes/Vox

# 4. Launch; Vox installs/starts its LaunchAgent again.
open /Applications/Vox.app
```

Run each stage only after the preceding stage succeeds. If Gatekeeper blocks
the first open, review the downloaded release and use **Open Anyway** in
System Settings → Privacy & Security.

If the volume mounts as `/Volumes/Vox 1` (because a stale `/Volumes/Vox`
exists), adjust the path or eject the older one first with
`hdiutil detach /Volumes/Vox`.

## Verifying the update worked

```sh
# Bundle version
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  /Applications/Vox.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  /Applications/Vox.app/Contents/Info.plist

# LaunchAgent process and running executable
launchctl print "gui/$(id -u)/com.andykumeda.vox"

# Process is the new bundle (not a stale one)
pgrep -fl vox

# Live log — dictate a short sentence and verify it appears in the target app
tail -f ~/Library/Logs/vox.log
```

If `Fn press` does not appear after holding Fn, **Input Monitoring** is
the most likely missing grant. The startup banner in `~/Library/Logs/vox.log`
includes `AXIsProcessTrusted=true/false` for Accessibility and `mic permission
granted=true/false` for Microphone — but it does **not** log Input
Monitoring status, so a missing IM grant is silent. Check the pane
manually.

## Troubleshooting

**Sparkle says "An error occurred in retrieving update information."**
Check the network and the actual feed. The repository uses GitHub Pages from
`main` / `/docs`; a Pages configuration or propagation problem can make it
unavailable. Verify that the response is a valid appcast containing the expected
version, not merely a successful HTTP status:

```sh
curl --fail --silent --show-error --location \
  https://andykumeda.github.io/vox/appcast.xml -o /tmp/vox-appcast.xml
xmllint --noout /tmp/vox-appcast.xml
rg 'sparkle:(shortVersionString|version)' /tmp/vox-appcast.xml
```

A 404 can also mean the feed path is wrong or a deployment has not propagated.
A 200 response alone does not verify XML, the advertised release, or its asset.

**Sparkle downloads but install fails.** Check that the DMG asset is
anonymously downloadable:

```sh
# Replace VERSION with the version advertised in the appcast.
curl --fail --silent --show-error --location --head \
  'https://github.com/andykumeda/vox/releases/download/vVERSION/Vox.dmg'
```

Follow redirects through to the final response. A successful download still
needs to match the appcast length and Sparkle signature; for release validation,
compare the downloaded SHA-256 with the packaged DMG and run `hdiutil verify`.
A 404 can mean the version or asset is missing, or the repository is private.

**App launches but the menu bar icon doesn't appear.** Another instance
may be running from a different location. Inspect `pgrep -fl vox` and the
LaunchAgent state above. Quit the old app normally, then open
`/Applications/Vox.app`; for the installed supervised app, restart it with
`launchctl kickstart -k "gui/$(id -u)/com.andykumeda.vox"`.

**App appears in Input Monitoring but events still don't fire.** Toggle
it off and back on, then quit and relaunch Vox. macOS sometimes caches
a stale grant against an old code-signing requirement. If the entry is absent,
add `/Applications/Vox.app` again, then quit and relaunch Vox.

**Fn key opens emoji picker instead of recording.** System Settings →
Keyboard → "Press 🌐 key to" → set to *Do Nothing*. Otherwise macOS
intercepts Fn before Vox sees it.

**You moved Vox.app to a new location.** Keep the development and release
installation at `/Applications/Vox.app`. LaunchServices and the per-user
LaunchAgent can otherwise continue referring to the prior bundle. Relaunch with
`open /Applications/Vox.app` or restart the LaunchAgent explicitly.
