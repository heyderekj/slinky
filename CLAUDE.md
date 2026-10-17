# Slinky — Agent Rules

**Slinky keeps secrets out of your files.** The third app in Derek Castelli's family (Dinky makes files smaller, Binky sorts your files). Native macOS 26+ app for developer secrets: API keys, project .env variables, 2FA recovery codes, and anything a website says to store somewhere safe. Agents use secrets without seeing them (CLI and MCP land in the agents milestone).

## Ownership
- Slinky is made by **Testament Made, LLC**, the same as Dinky and Binky. Use it in `LICENSE` (MIT), the Info.plist copyright (`© 2026 Testament Made, LLC`), the About panel credits, and the site footer.
- Support email: help@slinkyfiles.com (domain to be set up).

## Security rules (non-negotiable)
- Secret values never go into: UserDefaults/@AppStorage, logs, print(), notifications, crash reports, Spotlight, file names, URLs, or test fixtures that look real. Tests use obviously fake values (`EXAMPLE`).
- Only `SlinkyCoreVault` touches crypto and the keychain. Never use `/usr/bin/security`. Never fall back silently to weaker storage.
- The vault key lives in memory only while unlocked (`VaultSession`); locking drops it.
- Clipboard writes go through `Clipboard.copy` (concealed, transient, current-host-only, auto-clear).
- Nothing in an MCP/CLI response may contain or be derived from a value (no hashes, lengths, prefixes beyond `Peek`).
- Shortcuts (`Slinky/Intents/`): no intent returns a value. Items are exposed by name only, and only while unlocked. "Copy from Slinky" asks for Touch ID every time (any app can run a shortcut) and copies through `Clipboard.copy`. "Add to Slinky" opens Add Item for the person to check; it never saves on its own.
- Copy that promises safety must stay honest and plain. Never overclaim what Slinky protects against.

## Size and dependencies (from the family rules)
- Apple frameworks only. No SPM or CocoaPods dependencies without Derek's approval and a size justification. No web views, no Electron.
- SF Symbols and SVG over raster assets.

## Signing
- Free Apple Development identity, SHA-1 `1C79F5AFAA48ECA90E05A0A01B15E715BF1BBDEB`, **Team ID `B3U6BXA8KP`** (the `QHT464P5ZY` in the certificate name is a personal ID, not the team).
- Manual signing, hardened runtime, no restricted entitlements, no `get-task-allow` in Release.
- See `docs/spike-results.md` for why this works without a paid account.

## Layout
- `Slinky/` — app (SwiftUI, Swift 6, MainActor by default). The Xcode project uses folder-synchronized groups: add files to the folder, never edit the project for them.
- `SlinkyCore/` — SwiftPM package: `SlinkyCoreShared` (models, detection, .env), `SlinkyCoreVault` (Secure Enclave + Recovery Key + vault file), `SlinkyCLI`.
- `docs/` — plan, brief, layouts, research, test plan and results. `design/icon/` — icon sources and generators.
- `spike/` — the throwaway feasibility test. Don't build on it.

## Design
- Brand: clear, glassy, white, glacier/ice blue. Accent `#4a7aa3` light / `#a9c7dc` dark. Glass on chrome (sidebars, toolbars, panels, cards that float); values on opaque cool "paper" (`Color.paper`).
- Layouts from `docs/slinky-layouts.html`: A (.env project view), B (Library shelf), C (Quick Access ⌥⌘K), D (agent receipts, later), F (menu bar stack).
- Voice: see `VOICE.md`. Plain, serious, non-technical, for everyone. No clever labels in the app.
- **Design: read `docs/DESIGN.md` before any UI work.** It holds the principles, every reference and what we took from it, and decisions already made. No welcome screens or wizards (family rule).
