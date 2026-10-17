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
