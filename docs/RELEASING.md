# Releasing Vox

All public DMGs and Sparkle updates must be built on the Mac mini
(`AKsMini`). The Mini holds both release secrets:

- macOS code-signing identity: `vox-dev`
- Sparkle EdDSA private key used by `sign_update`

These are separate signatures. `scripts/build-app.sh` applies the macOS
signature to the app and its nested Sparkle helpers. Sparkle's `sign_update`
then signs the finished DMG for the update feed.

## Canonical macOS signing identity

The canonical `vox-dev` certificate SHA-1 is:

```text
406E1921DF57A0FC9CFE620F5FBC0524D1BB201E
```

Do not generate a replacement certificate or select another local identity
for a release. A different certificate changes Vox's designated requirement
and can invalidate Accessibility, Input Monitoring, Microphone, and Screen
Recording grants on installed Macs.

If both the Mac mini and MacBook install local development builds, they must
use the exact same exported `vox-dev` certificate and private key. Two
certificates with the same display name are still different identities when
their fingerprints differ.

## Release signing preflight

Run this on `AKsMini` before changing a version, building a DMG, or tagging a
release:

```sh
hostname
security find-identity -v -p codesigning
```

Confirm:

- Hostname is `AKsMini`.
- `vox-dev` is listed.
- Its SHA-1 is exactly
  `406E1921DF57A0FC9CFE620F5FBC0524D1BB201E`.
- `git status --short` contains only the intended release changes.

Stop if the identity is missing or its SHA differs. Do not accept the
ad-hoc-signing fallback for a release.

## Build and verify

```sh
# Build the app, sign nested Sparkle helpers inside-out, and package the DMG.
./scripts/make-dmg.sh

# Verify the app bundle and the identity embedded in its requirement.
codesign --verify --deep --strict --verbose=2 dist/Vox.app
codesign -d -r- dist/Vox.app 2>&1
```

The final command must report:

```text
designated => identifier "com.andykumeda.vox" and certificate leaf = H"406e1921df57a0fc9cfe620f5fbc0524d1bb201e"
```

Do not publish if the requirement contains a different certificate hash or
is reduced to an ad-hoc/CDHash identity.

## Sign the Sparkle update

```sh
.build/artifacts/sparkle/Sparkle/bin/sign_update dist/Vox.dmg
```

Copy the resulting `sparkle:edSignature` and `length` into the new top
`<item>` in `docs/appcast.xml`.

## Release checklist

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in
   `Resources/Info.plist`.
2. Run the signing preflight above.
3. Run `swift test`.
4. Run `./scripts/run-dictation-regression.sh`.
5. Run `./scripts/make-dmg.sh`.
6. Verify the app signature and designated requirement.
7. Run Sparkle `sign_update` and update `docs/appcast.xml`.
8. Review the diff, commit, tag, and push.
9. Create the GitHub release and attach `dist/Vox.dmg`.
10. Install through Sparkle on the MacBook and smoke-test local Fn recording,
    paste, and any changed OS integration.

Example publication commands:

```sh
git add Resources/Info.plist docs/appcast.xml
git commit --no-gpg-sign -m "release: 0.X.Y — …"
git tag v0.X.Y
git push origin main
git push origin v0.X.Y
gh release create v0.X.Y --title "Vox 0.X.Y" --notes "…" dist/Vox.dmg
```

## TCC recovery after an update

A stable signer greatly reduces permission churn, but macOS can still retain
a stale Input Monitoring record. If Vox is enabled in both Accessibility and
Input Monitoring, `hotkey.start() -> true` appears in the log, and Fn still
does not produce an `Fn press` line, reset only Vox's Input Monitoring record:

```sh
tccutil reset ListenEvent com.andykumeda.vox
```

Then add `/Applications/Vox.app` back under System Settings → Privacy &
Security → Input Monitoring, quit Vox, and relaunch it.
