#!/bin/zsh
# Builds the Glidepath 2.0 native prototype and launches it as a real .app bundle.
set -euo pipefail
cd "$(dirname "$0")"
# The SwiftUI macros (@State, @Observable) need the full Xcode toolchain, not just Command Line Tools.
if [[ -d /Applications/Xcode.app ]]; then export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; fi
swift build -c release
APP=build/Glidepath.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/Glidepath" "$APP/Contents/MacOS/Glidepath"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Glidepath</string>
  <key>CFBundleDisplayName</key><string>Glidepath</string>
  <key>CFBundleIdentifier</key><string>dev.glidepath.prototype.v2</string>
  <key>CFBundleExecutable</key><string>Glidepath</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.0-prototype</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><false/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
# Only quit this prototype, never the installed glidepath app.
PROTO="v2-native/build/Glidepath.app/Contents/MacOS/Glidepath"
pkill -f "$PROTO" 2>/dev/null || true
for _ in 1 2 3 4 5 6; do pgrep -f "$PROTO" >/dev/null || break; sleep 0.5; done
pkill -9 -f "$PROTO" 2>/dev/null || true; sleep 0.3
open "$APP"
