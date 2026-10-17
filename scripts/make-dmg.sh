#!/bin/bash
# make-dmg.sh <version> <path/to/Slinky.app>
# The install window: Slinky on the left, Applications on the right, on the glacier background from
# design/dmg (make_background.py). Window content is 600 x 380; icons are centered at (160,178) and (440,178).
set -e
VERSION="$1"; APP="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist/Slinky-$VERSION.dmg"
mkdir -p "$ROOT/dist"
rm -f "$OUT"
create-dmg \
  --volname "Slinky" \
  --volicon "$APP/Contents/Resources/AppIcon.icns" \
  --background "$ROOT/design/dmg/dmg-background.tiff" \
  --window-pos 220 160 \
  --window-size 600 380 \
  --icon-size 128 \
  --text-size 13 \
  --icon "Slinky.app" 160 178 \
  --hide-extension "Slinky.app" \
  --app-drop-link 440 178 \
  --no-internet-enable \
  "$OUT" "$APP" >/dev/null
echo "→ $OUT"
