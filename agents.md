# Agent notes — Slinky

## Build and test
```bash
# Core package (models, detection, vault) — the primary test gate
cd SlinkyCore && swift test

# App (shared scheme; derived data kept in ./build so it doesn't collide with Xcode)
xcodebuild -project Slinky.xcodeproj -scheme Slinky -configuration Debug -destination 'platform=macOS' -derivedDataPath build/dd build
open build/dd/Build/Products/Debug/Slinky.app
```

## Gotchas
- Environment objects: put `.environment(model)` outermost on a scene's root, after `.background`/`.overlay` helpers, or SwiftUI crashes with "No Observable object of type AppModel".
- The vault lives at `~/Library/Application Support/Slinky/vault.slinky`. Real data. Don't delete it to "reset" during development without asking Derek.
- Keychain items: service `com.slinky.app`, account `vault-enclave-key`.
- Quick Access is an `NSPanel` (non-activating, can become key) hosting SwiftUI; the global hotkey is Carbon `RegisterEventHotKey` (no Accessibility permission).


## Release
- `./release.sh 1.0.0` runs core tests, builds Release (Apple Development signing, hardened runtime, no entitlements), and writes `dist/Slinky-1.0.0.dmg` and `.zip`, then updates `Casks/slinky.rb`. Nothing is pushed.
- `./release.sh 1.0.0 --publish` also commits, tags, pushes and creates the GitHub release. Needs a remote and `gh`. Only with Derek's go-ahead.
- Check a build: `codesign -dvv build/release/Build/Products/Release/Slinky.app` should show TeamIdentifier B3U6BXA8KP and `flags=0x10000(runtime)`; `codesign -d --entitlements -` should print none.
