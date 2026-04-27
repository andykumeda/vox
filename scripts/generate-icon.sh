#!/usr/bin/env bash
# Generate Resources/AppIcon.icns from a single 1024x1024 master PNG
# that we render via scripts/generate-icon.swift.
set -euo pipefail

cd "$(dirname "$0")/.."

MASTER="Resources/AppIcon.png"
ICONSET="dist/AppIcon.iconset"
OUT="Resources/AppIcon.icns"

echo "→ rendering master 1024x1024 PNG"
swift scripts/generate-icon.swift "$MASTER"

echo "→ producing iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# Apple's required set for .icns: 16, 32, 128, 256, 512 @ 1x + @ 2x
declare -a SIZES=(
    "16    icon_16x16.png"
    "32    icon_16x16@2x.png"
    "32    icon_32x32.png"
    "64    icon_32x32@2x.png"
    "128   icon_128x128.png"
    "256   icon_128x128@2x.png"
    "256   icon_256x256.png"
    "512   icon_256x256@2x.png"
    "512   icon_512x512.png"
    "1024  icon_512x512@2x.png"
)

for entry in "${SIZES[@]}"; do
    size=$(echo "$entry" | awk '{print $1}')
    name=$(echo "$entry" | awk '{print $2}')
    sips -z "$size" "$size" "$MASTER" --out "$ICONSET/$name" >/dev/null
done

echo "→ iconutil → .icns"
iconutil -c icns "$ICONSET" -o "$OUT"
rm -rf "$ICONSET"

echo "✓ wrote $OUT"
