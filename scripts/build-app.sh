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
SIGN_IDENTITY="-"
if security find-identity -v 2>/dev/null | grep -q '"vox-dev"'; then
    SIGN_IDENTITY="vox-dev"
    echo "→ codesign (vox-dev — permissions will persist)"
else
    echo "→ codesign (ad-hoc — permissions will reset on each rebuild)"
    echo "   run ./scripts/create-dev-cert.sh once to make permissions persistent"
fi

codesign --force --sign "$SIGN_IDENTITY" \
    --entitlements Resources/vox.entitlements \
    --options runtime \
    --timestamp=none \
    "$APP_PATH" >/dev/null

echo "✓ built $APP_PATH"
echo
echo "Launch: open $APP_PATH"
echo "Logs:   tail -f ~/Library/Logs/vox.log"
