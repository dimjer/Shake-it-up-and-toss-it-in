#!/bin/zsh
# Builds Toss.app, installs it into ~/Applications and launches it.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Toss.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
  Sources/*.swift -o "$APP/Contents/MacOS/Toss"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Toss</string>
  <key>CFBundleDisplayName</key><string>Toss</string>
  <key>CFBundleIdentifier</key><string>nl.nidaros.toss</string>
  <key>CFBundleExecutable</key><string>Toss</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>CFBundleIconFile</key><string>Toss</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

swift Tools/make_icon.swift build/Toss.iconset
iconutil -c icns build/Toss.iconset -o "$APP/Contents/Resources/Toss.icns"

codesign --force --sign - "$APP"

pkill -x Toss 2>/dev/null || true
while pgrep -x Toss >/dev/null; do sleep 0.1; done   # let the old copy quit, or `open` fails with -600
mkdir -p ~/Applications
rm -rf ~/Applications/Toss.app
cp -R "$APP" ~/Applications/
open ~/Applications/Toss.app
echo "Installed ~/Applications/Toss.app"
