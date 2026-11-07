#!/bin/zsh
# Builds Sweep.app into /Applications, then restarts it so the new build is running.
set -euo pipefail
cd "$(dirname "$0")"
DEST=/Applications/Sweep.app
# Build in a temporary folder and swap the finished app in, so Finder and Spotlight never see a
# half-built app. If they do, they cache it with a "can't open" icon.
APP=$(mktemp -d)/Sweep.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
ICONSET=$(mktemp -d)/Sweep.iconset
swift make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Sweep.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Sweep</string>
  <key>CFBundleIdentifier</key><string>local.sweep</string>
  <key>CFBundleExecutable</key><string>Sweep</string>
  <key>CFBundleIconFile</key><string>Sweep</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
swiftc -O -parse-as-library -swift-version 5 Sweep.swift -o "$APP/Contents/MacOS/Sweep"
codesign --force --sign - "$APP" >/dev/null
pkill -x Sweep || true
rm -rf "$DEST"
mv "$APP" "$DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
open "$DEST"
echo "Built and opened $DEST"
