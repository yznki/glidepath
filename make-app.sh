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

# App icon. The binary draws the icon at any size: 64 px and below use the simplified drawing (slope and amber
# light, no runway), larger sizes the full one. sips resizes the 1024 master for the sizes the binary does not draw.
"$BIN" --render-icon build/icon-1024.png 1024
for px in 16 32 64; do
    "$BIN" --render-icon "build/icon-${px}.png" "$px"
done
cp build/icon-16.png "$ICONSET/icon_16x16.png"
cp build/icon-32.png "$ICONSET/icon_16x16@2x.png"
cp build/icon-32.png "$ICONSET/icon_32x32.png"
cp build/icon-64.png "$ICONSET/icon_32x32@2x.png"
for s in 128 256 512; do
    sips -z "$s" "$s" build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z "$((s * 2))" "$((s * 2))" build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep -s - "$APP"
echo "built $APP"
