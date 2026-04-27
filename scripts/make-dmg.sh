#!/usr/bin/env bash
# Build Vox and package it as a drag-to-install DMG (dist/Vox.dmg).
# Runs scripts/build-app.sh first. Requires hdiutil (ships with macOS).
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Vox"
APP_PATH="dist/${APP_NAME}.app"
DMG_VOL="${APP_NAME}"
DMG_NAME="${APP_NAME}.dmg"
STAGE="dist/dmg-stage"
OUT="dist/${DMG_NAME}"

echo "→ building app"
./scripts/build-app.sh >/dev/null

echo "→ staging DMG contents"
rm -rf "$STAGE" "$OUT"
mkdir -p "$STAGE" dist
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "→ creating DMG ($OUT)"
hdiutil create \
    -volname "$DMG_VOL" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$OUT" >/dev/null

rm -rf "$STAGE"

SIZE=$(du -h "$OUT" | awk '{print $1}')
echo "✓ $OUT ($SIZE)"
echo
echo "Test install:     open $OUT   # then drag Vox.app onto Applications"
echo "GitHub release:   gh release create v0.X.Y --title '$APP_NAME 0.X.Y' $OUT"
