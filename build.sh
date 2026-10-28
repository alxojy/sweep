#!/bin/zsh
# Builds Sweep.app next to this script. Run it, then open Sweep.app.
set -euo pipefail
cd "$(dirname "$0")"
APP=Sweep.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Sweep</string>
  <key>CFBundleIdentifier</key><string>local.sweep</string>
  <key>CFBundleExecutable</key><string>Sweep</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
swiftc -O -parse-as-library -swift-version 5 Sweep.swift -o "$APP/Contents/MacOS/Sweep"
codesign --force --sign - "$APP" >/dev/null
echo "Built $(pwd)/$APP"
