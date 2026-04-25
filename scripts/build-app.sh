#!/usr/bin/env bash
# Build Vox as a release binary and wrap it in a macOS .app bundle.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
BINARY_NAME="vox"
APP_NAME="Vox"
BUILD_DIR=".build/arm64-apple-macosx/$CONFIG"
APP_PATH="build/${APP_NAME}.app"
ICON_SRC="Resources/AppIcon.icns"

echo "→ swift build -c $CONFIG"
swift build -c "$CONFIG"

if [ ! -f "$ICON_SRC" ]; then
    echo "→ generating AppIcon.icns (first build)"
    ./scripts/generate-icon.sh
fi

echo "→ assembling $APP_PATH"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

cp "$BUILD_DIR/$BINARY_NAME" "$APP_PATH/Contents/MacOS/$BINARY_NAME"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
cp "$ICON_SRC" "$APP_PATH/Contents/Resources/AppIcon.icns"

# Prefer the persistent "vox-dev" self-signed identity (created by
# scripts/create-dev-cert.sh) so TCC permissions stick across rebuilds.
# Fall back to ad-hoc if the identity isn't installed.
#
# Probe the login keychain directly (not `find-identity -v`) for two reasons:
#   1. On MDM-managed Macs the self-signed cert can't reach the System
#      keychain, so it lists as CSSMERR_TP_NOT_TRUSTED and `-v` filters it
#      out — but codesign can still sign with the private key just fine.
#   2. Prior runs sometimes left duplicate "vox-dev" certs in System.keychain
#      making `--sign vox-dev` ambiguous. Sign by SHA-1 hash to disambiguate.
SIGN_IDENTITY="-"
LOGIN_KC="$HOME/Library/Keychains/login.keychain-db"
# Probe in two phases:
#   (a) default search list with -v — catches the common case where cert lives
#       in System.keychain (System-trusted) and key in login.keychain.
#   (b) login keychain alone, no -v — catches MDM-managed Macs where the
#       cert can't reach System.keychain and lists as CSSMERR_TP_NOT_TRUSTED
#       (filtered by -v) but the private key + cert are in login.keychain.
VOX_MATCHES="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk '/"vox-dev"/ {print $2}')"
if [ -z "$VOX_MATCHES" ]; then
    VOX_MATCHES="$(security find-identity "$LOGIN_KC" 2>/dev/null \
        | awk '/"vox-dev"/ {print $2}')"
fi
VOX_MATCH_COUNT="$(printf '%s\n' "$VOX_MATCHES" | grep -c . || true)"
if [ "$VOX_MATCH_COUNT" -gt 1 ]; then
    echo "⚠ found $VOX_MATCH_COUNT 'vox-dev' identities; using first."
    echo "  consider re-running ./scripts/create-dev-cert.sh to dedupe."
fi
VOX_SHA="$(printf '%s\n' "$VOX_MATCHES" | head -n 1)"
BUNDLE_ID="com.andykumeda.vox"
REQ_ARG=()
if [ -n "$VOX_SHA" ]; then
    SIGN_IDENTITY="$VOX_SHA"
    echo "→ codesign (vox-dev $VOX_SHA — permissions will persist)"
    # Pin the designated requirement to the cert SHA so the bundle's identity
    # is stable across rebuilds. Without this the DR defaults to something
    # that embeds the CDHash, which changes every build and invalidates
    # Keychain ACLs ("Always Allow" re-prompting after every rebuild).
    # The `=` prefix marks it as an inline requirement string; `designated =>`
    # names which slot it binds to.
    REQ_ARG=(-r "=designated => identifier \"$BUNDLE_ID\" and certificate leaf = H\"$VOX_SHA\"")
else
    echo "→ codesign (ad-hoc — permissions will reset on each rebuild)"
    echo "   run ./scripts/create-dev-cert.sh once to make permissions persistent"
fi

codesign --force --sign "$SIGN_IDENTITY" \
    "${REQ_ARG[@]}" \
    --entitlements Resources/vox.entitlements \
    --options runtime \
    --timestamp=none \
    "$APP_PATH" >/dev/null

echo "✓ built $APP_PATH"
echo
echo "Launch: open $APP_PATH"
echo "Logs:   tail -f ~/Library/Logs/vox.log"
