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
echo "→ Signed: $(codesign -dvv "$APP" 2>&1 | grep -E '^Authority=Apple Development' | head -1)"

# 4. Package
scripts/make-dmg.sh "$VERSION" "$APP"

echo "→ dist/Slinky-$VERSION.zip"
rm -f "dist/Slinky-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/Slinky-$VERSION.zip"

SHA=$(shasum -a 256 "dist/Slinky-$VERSION.zip" | awk '{print $1}')
sed -i '' "s/version \".*\"/version \"$VERSION\"/" Casks/slinky.rb
sed -i '' "s/sha256 \".*\"/sha256 \"$SHA\"/" Casks/slinky.rb
echo "→ Casks/slinky.rb updated (sha256 $SHA)"

if [ "$PUBLISH" = false ]; then
  echo ""
  echo "✓ Built. Nothing was pushed. To publish: commit the version bump, then run ./release.sh $VERSION --publish"
  exit 0
fi

# 5. Publish
git add Slinky.xcodeproj/project.pbxproj Casks/slinky.rb
git commit -m "Release v$VERSION"
git tag "v$VERSION"
git push && git push --tags
gh release create "v$VERSION" "dist/Slinky-$VERSION.dmg" "dist/Slinky-$VERSION.zip" \
  --title "Slinky $VERSION" --notes "$(git log --pretty='- %s' "$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || git rev-list --max-parents=0 HEAD)"..HEAD^)"
echo "✓ Published v$VERSION"
