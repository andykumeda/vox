#!/usr/bin/env bash
# Build Vox as a release binary and wrap it in a macOS .app bundle.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
BINARY_NAME="vox"
APP_NAME="Vox"
APP_PATH="dist/${APP_NAME}.app"
INSTALL_TO_APPLICATIONS="${INSTALL_TO_APPLICATIONS:-1}"
INSTALL_PATH="${INSTALL_PATH:-/Applications/${APP_NAME}.app}"
ICON_SRC="Resources/AppIcon.icns"

echo "→ swift build -c $CONFIG"
swift build -c "$CONFIG"
BUILD_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BUILT_BINARY="$BUILD_DIR/$BINARY_NAME"
if [ ! -x "$BUILT_BINARY" ]; then
    echo "✗ SwiftPM product missing or not executable: $BUILT_BINARY" >&2
    exit 1
fi

if [ ! -f "$ICON_SRC" ]; then
    echo "→ generating AppIcon.icns (first build)"
    ./scripts/generate-icon.sh
fi

echo "→ assembling $APP_PATH"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

cp "$BUILT_BINARY" "$APP_PATH/Contents/MacOS/$BINARY_NAME"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
cp "$ICON_SRC" "$APP_PATH/Contents/Resources/AppIcon.icns"
cp Resources/AppIcon-Command.png "$APP_PATH/Contents/Resources/"
cp Resources/help.md "$APP_PATH/Contents/Resources/"

# Embed Sparkle.framework for in-app updates.
SPARKLE_FRAMEWORK="$BUILD_DIR/Sparkle.framework"
if [ -d "$SPARKLE_FRAMEWORK" ]; then
    mkdir -p "$APP_PATH/Contents/Frameworks"
    rm -rf "$APP_PATH/Contents/Frameworks/Sparkle.framework"
    cp -R "$SPARKLE_FRAMEWORK" "$APP_PATH/Contents/Frameworks/"
    # SwiftPM doesn't add an rpath that points into the bundled Frameworks
    # dir. Add it ourselves so dyld can resolve @rpath/Sparkle.framework.
    install_name_tool -add_rpath "@executable_path/../Frameworks" \
        "$APP_PATH/Contents/MacOS/$BINARY_NAME" 2>/dev/null || true
fi

# Prefer an Apple-issued team identity. Modern macOS Keychain ACLs record its
# stable `teamid:` partition, while a self-signed identity is recorded as a
# changing `cdhash:` partition and makes "Always Allow" prompt after rebuilds.
# Developer ID is preferred when installed; Apple Development is suitable for
# these personal builds and still supplies the stable team partition.
#
# Keep the historical `vox-dev` identity as a fallback for Macs without an
# Apple-issued identity. Its explicit designated requirement still helps TCC,
# but Keychain authorization may repeat after changed builds on modern macOS.
SIGN_IDENTITY="-"
LOGIN_KC="$HOME/Library/Keychains/login.keychain-db"
BUNDLE_ID="com.andykumeda.vox"
REQ_ARG=()
VALID_IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
TEAM_SHA="$(printf '%s\n' "$VALID_IDENTITIES" \
    | awk '/"Developer ID Application:/ {print $2; exit}')"
TEAM_LABEL="Developer ID Application"
if [ -z "$TEAM_SHA" ]; then
    TEAM_SHA="$(printf '%s\n' "$VALID_IDENTITIES" \
        | awk '/"Apple Development:/ {print $2; exit}')"
    TEAM_LABEL="Apple Development"
fi

if [ -n "$TEAM_SHA" ]; then
    SIGN_IDENTITY="$TEAM_SHA"
    echo "→ codesign ($TEAM_LABEL $TEAM_SHA — stable Keychain team identity)"
else
    # Probe the login keychain without `-v` as an MDM fallback: an untrusted
    # self-signed private key can still be used by codesign.
    VOX_SHA="$(security find-identity "$LOGIN_KC" 2>/dev/null \
        | awk '/"vox-dev"/ {print $2; exit}')"
    if [ -n "$VOX_SHA" ]; then
        SIGN_IDENTITY="$VOX_SHA"
        echo "→ codesign (vox-dev $VOX_SHA — Keychain may re-prompt after rebuilds)"
        # Pin the designated requirement to the cert SHA so the bundle's identity
        # is stable for TCC even though modern Keychain partitions remain cdhashes.
        # The `=` prefix marks it as an inline requirement string; `designated =>`
        # names which slot it binds to.
        REQ_ARG=(-r "=designated => identifier \"$BUNDLE_ID\" and certificate leaf = H\"$VOX_SHA\"")
    else
        echo "→ codesign (ad-hoc — permissions will reset on each rebuild)"
        echo "   install an Apple Development/Developer ID identity or run ./scripts/create-dev-cert.sh"
    fi
fi

# Sign Sparkle's nested helpers inside-out, then the framework, then the app.
SPARKLE_BUNDLE="$APP_PATH/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE_BUNDLE" ]; then
    SPARKLE_VER="$SPARKLE_BUNDLE/Versions/B"
    [ -d "$SPARKLE_VER" ] || SPARKLE_VER="$(/bin/ls -d "$SPARKLE_BUNDLE/Versions/"[A-Z] 2>/dev/null | head -n 1)"
    if [ -n "$SPARKLE_VER" ] && [ -d "$SPARKLE_VER" ]; then
        for xpc in "$SPARKLE_VER/XPCServices/"*.xpc; do
            [ -d "$xpc" ] || continue
            codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp=none "$xpc" >/dev/null
        done
        if [ -d "$SPARKLE_VER/Updater.app" ]; then
            codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp=none --deep "$SPARKLE_VER/Updater.app" >/dev/null
        fi
        if [ -f "$SPARKLE_VER/Autoupdate" ]; then
            codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp=none "$SPARKLE_VER/Autoupdate" >/dev/null
        fi
    fi
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp=none "$SPARKLE_BUNDLE" >/dev/null
fi

codesign --force --sign "$SIGN_IDENTITY" \
    "${REQ_ARG[@]}" \
    --entitlements Resources/vox.entitlements \
    --options runtime \
    --timestamp=none \
    "$APP_PATH" >/dev/null

# Catch stale or incorrectly located SwiftPM products before installing or
# packaging them. Signing and rpath edits may change bytes, but not Mach-O UUIDs.
BUILT_UUIDS="$(xcrun dwarfdump --uuid "$BUILT_BINARY" \
    | awk '/^UUID:/ {print $2, $3}' \
    | LC_ALL=C sort)"
BUNDLED_UUIDS="$(xcrun dwarfdump --uuid "$APP_PATH/Contents/MacOS/$BINARY_NAME" \
    | awk '/^UUID:/ {print $2, $3}' \
    | LC_ALL=C sort)"
if [ -z "$BUILT_UUIDS" ] || [ "$BUILT_UUIDS" != "$BUNDLED_UUIDS" ]; then
    echo "✗ bundled executable does not match the SwiftPM product" >&2
    echo "  built:   ${BUILT_UUIDS:-missing} ($BUILT_BINARY)" >&2
    echo "  bundled: ${BUNDLED_UUIDS:-missing} ($APP_PATH/Contents/MacOS/$BINARY_NAME)" >&2
    exit 1
fi

if [ "$INSTALL_TO_APPLICATIONS" != "0" ]; then
    echo "→ installing $INSTALL_PATH"
    rm -rf "$INSTALL_PATH"
    ditto "$APP_PATH" "$INSTALL_PATH"
    codesign --verify --deep --strict "$INSTALL_PATH" >/dev/null
fi

echo "✓ built $APP_PATH"
if [ "$INSTALL_TO_APPLICATIONS" != "0" ]; then
    echo "✓ installed $INSTALL_PATH"
fi
echo
if [ "$INSTALL_TO_APPLICATIONS" != "0" ]; then
    echo "Launch: open $INSTALL_PATH"
else
    echo "Launch: open $APP_PATH"
fi
echo "Logs:   tail -f ~/Library/Logs/vox.log"
