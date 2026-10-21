#!/bin/bash
# Build "dist/Notch Agenti.app" (release, ad-hoc signed). install.sh calls this.
# Usage: bash scripts/build_app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/NotchAgenti"
APP="dist/Notch Agenti.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NotchAgenti"
cp -R Sounds "$APP/Contents/Resources/Sounds"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Notch Agenti</string>
  <key>CFBundleIdentifier</key><string>com.mattiacalastri.notch-agenti</string>
  <key>CFBundleExecutable</key><string>NotchAgenti</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>Notch Agenti porta in primo piano la scheda del terminale su cui clicchi.</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
plutil -lint "$APP/Contents/Info.plist" > /dev/null
echo "built: $APP"
