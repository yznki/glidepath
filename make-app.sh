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
FULL="assets/brand/icon.png"          # 1024 px, for 128 pt and up
SMALL="assets/brand/icon-small.png"   # 1024 px simplified artwork, for 16 and 32 pt

rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"

cp "$BIN" "$APP/Contents/MacOS/glidepath"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# The version comes from the Swift constant, so the bundle cannot drift from `glidepath --version`.
VERSION=$(sed -n 's/.*static let current = "\(.*\)".*/\1/p' Sources/Glidepath/Core/Version.swift)
[[ -n "$VERSION" ]] || { echo "no version found in Sources/Glidepath/Core/Version.swift" >&2; exit 1; }
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $VERSION" \
    "$APP/Contents/Info.plist"

# App icon: the iconset comes from the brand PNGs with sips; iconutil packs the .icns.
sips -z 16 16 "$SMALL" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$SMALL" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$SMALL" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$SMALL" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
for s in 128 256 512; do
    sips -z "$s" "$s" "$FULL" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z "$((s * 2))" "$((s * 2))" "$FULL" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep -s - "$APP"
echo "built $APP"
