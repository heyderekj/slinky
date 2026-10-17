#!/bin/bash
# Builds SlinkySpike.app with the CLI inside, signed with Derek's free Apple Development identity,
# hardened runtime on, no get-task-allow. Usage: ./build-app.sh [identity-sha1]
set -euo pipefail
cd "$(dirname "$0")"
IDENTITY="${1:-1C79F5AFAA48ECA90E05A0A01B15E715BF1BBDEB}"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"
APP="build/SlinkySpike.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/SlinkySpike" "$APP/Contents/MacOS/SlinkySpike"
cp "$BIN/slinky-spike" "$APP/Contents/MacOS/slinky-spike"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>SlinkySpike</string>
  <key>CFBundleIdentifier</key><string>com.slinky.spike</string>
  <key>CFBundleName</key><string>Slinky Test</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER:-1}</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --options runtime --timestamp=none -i com.slinky.spike.cli -s "$IDENTITY" "$APP/Contents/MacOS/slinky-spike"
codesign --force --options runtime --timestamp=none -s "$IDENTITY" "$APP"
echo "--- app signature"
codesign -dvv "$APP" 2>&1 | grep -E "Identifier|Authority=Apple Development|TeamIdentifier|flags|Runtime"
echo "--- cli signature"
codesign -dvv "$APP/Contents/MacOS/slinky-spike" 2>&1 | grep -E "Identifier|TeamIdentifier|flags"
echo "--- entitlements (expect none, so no get-task-allow)"
codesign -d --entitlements - "$APP" 2>&1 | tail -n +2 || true
echo "--- gatekeeper (expect rejected: not notarized)"
spctl -a -vv "$APP" 2>&1 || true
