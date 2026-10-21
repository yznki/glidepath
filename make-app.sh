#!/usr/bin/env bash
# Wraps the release binary into build/Glidepath.app (LSUIElement, ad-hoc signed).
# Uses Command Line Tools only. Pass --no-build to reuse an existing .build/release binary.
set -euo pipefail
cd "$(dirname "$0")"

if [[ "${1:-}" != "--no-build" ]]; then
    swift build -c release
fi

BIN=".build/release/glidepath"
APP="build/Glidepath.app"
ICONSET="build/AppIcon.iconset"

rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"

cp "$BIN" "$APP/Contents/MacOS/glidepath"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon: icon.swift draws a 1024 px PNG; sips makes the iconset sizes; iconutil packs the .icns.
swift icon.swift build/icon-1024.png >/dev/null
for s in 16 32 128 256 512; do
    sips -z "$s" "$s" build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z "$((s * 2))" "$((s * 2))" build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep -s - "$APP"
echo "built $APP"
