#!/bin/bash
# release.sh — build and package a Slinky release (same shape as Dinky's).
#
# Usage:
#   ./release.sh 1.0.0             # bump, test, build Release, make dist/Slinky-1.0.0.dmg + .zip, update the cask
#   ./release.sh 1.0.0 --publish   # also commit, tag, push and create the GitHub release (needs a remote + gh)
#
# Slinky is signed with the free Apple Development identity and isn't notarized (no paid account yet),
# so people open it once with System Settings › Privacy & Security › Open Anyway. The README says how.
#
# Prerequisites: create-dmg (brew install create-dmg); gh only for --publish.

set -e

VERSION=""
PUBLISH=false
for arg in "$@"; do
  case "$arg" in
    --publish) PUBLISH=true ;;
    *) VERSION="$arg" ;;
  esac
done
if [ -z "$VERSION" ]; then
  echo "Usage: ./release.sh <version> [--publish]"
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "✗ Commit or stash your changes first, so the release matches the repo."
  git status -sb
  exit 1
fi

APP="build/release/Build/Products/Release/Slinky.app"
mkdir -p dist

echo "▶ Slinky v$VERSION"

# 1. Version
OLD=$(grep "MARKETING_VERSION" Slinky.xcodeproj/project.pbxproj | head -1 | sed 's/.*= //;s/;//')
BUILD=$(grep "CURRENT_PROJECT_VERSION" Slinky.xcodeproj/project.pbxproj | head -1 | sed 's/.*= //;s/;//')
if [ "$OLD" != "$VERSION" ]; then
  echo "→ Version $OLD → $VERSION (build $((BUILD + 1)))"
  sed -i '' "s/MARKETING_VERSION = $OLD;/MARKETING_VERSION = $VERSION;/g" Slinky.xcodeproj/project.pbxproj
  sed -i '' "s/CURRENT_PROJECT_VERSION = $BUILD;/CURRENT_PROJECT_VERSION = $((BUILD + 1));/g" Slinky.xcodeproj/project.pbxproj
fi

# 2. Tests
echo "→ Core tests…"
(cd SlinkyCore && swift test 2>&1 | grep -E "Test run|✘|error:")

# 3. Build
echo "→ Building Release…"
xcodebuild -project Slinky.xcodeproj -scheme Slinky -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/release clean build | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
codesign --verify --deep --strict "$APP"
[ "$(lipo -archs "$APP/Contents/MacOS/Slinky")" = "arm64" ] || { echo "✘ Expected an Apple silicon-only build"; exit 1; }
# The Lock control extension (macOS 26+) ships inside the app: same identity, Apple silicon only, sandbox and nothing more.
CONTROLS="$APP/Contents/PlugIns/SlinkyControls.appex"
[ "$(lipo -archs "$CONTROLS/Contents/MacOS/SlinkyControls")" = "arm64" ] || { echo "✘ Expected an Apple silicon-only Lock control"; exit 1; }
[ "$(codesign -d --entitlements - --xml "$CONTROLS" 2>/dev/null | plutil -convert json -o - - | tr -d ' ')" = '{"com.apple.security.app-sandbox":true}' ] \
  || { echo "✘ The Lock control should have the app sandbox entitlement and nothing else"; exit 1; }
echo "→ Signed: $(codesign -dvv "$APP" 2>&1 | grep -E '^Authority=Apple Development' | head -1)"
# Debug-only tools (fake vaults, snapshots) must never ship.
if strings "$APP/Contents/MacOS/Slinky" | grep -q -e "--demo-data" -e "--render-snapshots" -e "DemoFixture"; then
  echo "✘ The Release build contains Debug-only demo code"; exit 1
fi

# 4. Package
scripts/make-dmg.sh "$VERSION" "$APP"

echo "→ dist/Slinky-$VERSION.zip"
rm -f "dist/Slinky-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/Slinky-$VERSION.zip"

# The oldest macOS this build runs on, from the app's own Info.plist. The cask, the site and the agent files
# follow it, so they never promise a Mac the release can't open.
MIN_MACOS=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$APP/Contents/Info.plist" | cut -d. -f1)
case "$MIN_MACOS" in
  14) MIN_NAME="macOS 14 Sonoma"; MIN_CASK=":sonoma" ;;
  15) MIN_NAME="macOS 15 Sequoia"; MIN_CASK=":sequoia" ;;
  26) MIN_NAME="macOS 26 Tahoe"; MIN_CASK=":tahoe" ;;
  # Check Homebrew's symbol for 27 before the first release that needs it (MacOS::SYMBOLS in brew).
  27) MIN_NAME="macOS 27 Golden Gate"; MIN_CASK=":golden_gate" ;;
  *) echo "✘ Unknown minimum macOS $MIN_MACOS; add it to release.sh"; exit 1 ;;
esac

SHA=$(shasum -a 256 "dist/Slinky-$VERSION.zip" | awk '{print $1}')
sed -i '' "s/version \".*\"/version \"$VERSION\"/" Casks/slinky.rb
sed -i '' "s/sha256 \".*\"/sha256 \"$SHA\"/" Casks/slinky.rb
sed -i '' "s/depends_on macos: :[a-z]*/depends_on macos: $MIN_CASK/" Casks/slinky.rb
echo "→ Casks/slinky.rb updated (sha256 $SHA)"

# 5. The website reads its version and download links from one file.
SIZE_MB=$(( ( $(stat -f%z "dist/Slinky-$VERSION.dmg") + 524288 ) / 1048576 ))   # the download size, which is what the site shows
cat > site/src/release.json <<JSON
{
  "version": "$VERSION",
  "dmg": "https://github.com/heyderekj/slinky/releases/download/v$VERSION/Slinky-$VERSION.dmg",
  "zip": "https://github.com/heyderekj/slinky/releases/download/v$VERSION/Slinky-$VERSION.zip",
  "sizeMB": $SIZE_MB,
  "minOS": "$MIN_NAME"
}
JSON
sed -i '' -E "s/macOS [0-9]+ (Sonoma|Sequoia|Tahoe|Golden Gate)/$MIN_NAME/g" site/public/llms.txt site/public/homepage.md
echo "→ site/src/release.json updated (v$VERSION, ${SIZE_MB} MB). Pushing main deploys the site."

if [ "$PUBLISH" = false ]; then
  echo ""
  echo "✓ Built. Nothing was pushed. To publish: commit the version bump, then run ./release.sh $VERSION --publish"
  exit 0
fi

# 6. Publish
git add Slinky.xcodeproj/project.pbxproj Casks/slinky.rb site/src/release.json site/public/llms.txt site/public/homepage.md
git commit -m "Release v$VERSION"
git tag "v$VERSION"
git push && git push --tags
gh release create "v$VERSION" "dist/Slinky-$VERSION.dmg" "dist/Slinky-$VERSION.zip" \
  --title "Slinky $VERSION" --notes "$(git log --pretty='- %s' "$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || git rev-list --max-parents=0 HEAD)"..HEAD^)"
echo "✓ Published v$VERSION"
