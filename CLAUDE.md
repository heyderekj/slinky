# Slinky — Agent Rules

**Slinky keeps secrets out of files.** The third app in Derek Castelli's family (Dinky makes files smaller, Binky sorts your files). Native macOS 15+ app for developer secrets (Liquid Glass on macOS 26, the standard look on 15): API keys, project .env variables, 2FA recovery codes, and anything a website says to store somewhere safe. Agents use secrets without seeing them (CLI and MCP land in the agents milestone).

## Ownership
- Slinky is made by **Testament Made, LLC**, the same as Dinky and Binky. Use it in `LICENSE` (MIT), the Info.plist copyright (`© 2026 Testament Made, LLC`), the About panel credits, and the site footer.
- Support email: derek@testamentmade.com, shared by Slinky, Dinky and Binky (Testament Made).

## Security rules (non-negotiable)
- Secret values never go into: UserDefaults/@AppStorage, logs, print(), notifications, crash reports, Spotlight, file names, URLs, or test fixtures that look real. Tests use obviously fake values (`EXAMPLE`).
- Only `SlinkyCoreVault` touches crypto and the keychain. Never use `/usr/bin/security`. Never fall back silently to weaker storage.
- The vault key lives in memory only while unlocked (`VaultSession`); locking drops it.
- Clipboard writes go through `Clipboard.copy` (concealed, transient, current-host-only, auto-clear).
- Nothing in an MCP/CLI response may contain or be derived from a value (no hashes, lengths, prefixes beyond `Peek`).
- Shortcuts (`Slinky/Intents/`): no intent returns a value. Items are exposed by name only, and only while unlocked. "Copy from Slinky" asks for Touch ID every time (any app can run a shortcut) and copies through `Clipboard.copy`. "Add to Slinky" opens Add Item for the person to check; it never saves on its own.
- Copy that promises safety must stay honest and plain. Never overclaim what Slinky protects against.
- Network: only the update check (can be turned off) and website icons (off unless turned on; `WebsiteIcons`: https only, straight to the site, no cookies, icons stored in the vault). Send to Host (`HostPush`) runs the host's own CLI only when the person starts it, after a preview and Touch ID; values on stdin (Netlify: a 0600 temp file deleted at once), never in argv. Sync (`VaultSync`, off unless turned on; Derek approved 2026-10-22): Slinky writes only an encrypted copy of the vault (the backup format, no Touch ID key) to a folder the person chooses; their own sync service moves it. Slinky makes no request for it. Any new request needs Derek's OK and honest copy everywhere Slinky says what goes online.
- The `slinky` command is the app's own binary started with `--slinky-cli` (`Slinky/Agents/`). The app checks each socket caller's code signature against its own designated requirement and names who's asking from the process tree. Values leave only for an approved `env` request (run/export/xcconfig). Agents: `slinky run` only, refusals in `Broker.agentRefusal`, live and never-for-agents items held back, approvals never reused. MCP tools return names only.
- Sharing (`Sharing.swift`, `SharedProject.swift`; Derek approved the plan 2026-10-29): crypto only in `SlinkyCoreVault`. Cards are public keys only. Share files and shared-project files are encrypted and signed; Slinky writes them to a temporary folder or a team folder the person chose and sends nothing itself (no new request, like `VaultSync`). People and sharing never reach the CLI or MCP. Opening anything sealed to this Mac needs Touch ID; signing doesn't, so the app asks first for every deliberate share and member change. Copy must say that people keep what they saw and that removal means making new keys.
- Post-quantum: on macOS 26+ the vault key and sharing envelopes are hybrid (P-256 + ML-KEM-768, `Envelope`), signatures add ML-DSA-65. Never drop the classic half.
- Leak finder (`LeakFinder`) and Activity: names and places only. Leak results live in memory; Activity lives in the vault.
- Icons and Apple Intelligence matching get names, "from" and link sites only, never values. Icon caches and Add Item drafts are memory only and clear on lock.

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
- Brand: clear, glassy, white, **glacier cyan** (changed from ice blue on 2026-10-17 so Slinky holds its own spot next to Harvous's blue in the Testament Made suite). Accent `#0b7f8f` in light and dark mode (it carries white text). Icon fill `#1ac8db`.
- Apple silicon only (arm64). Set at the project level and checked by `release.sh`.
- macOS 27 only (behind `if #available(macOS 27, *)`): the AppKit status item with expanded-interface sessions (`StatusItemController`; `MenuBarExtra` stays for 15–26), App Intents execution targets and error mapping, notification entity links, `SymmetricKey(copyingWithZeroing:)`.
- The `SlinkyControls` extension (macOS 26+, Lock control) knows nothing about the vault: it posts `com.slinky.app.lock` and the app locks. Sandbox entitlement only; `release.sh` checks it.
- Runs on macOS 15 Sequoia and later. Liquid Glass APIs are macOS 26 only: use the helpers in `Slinky/Views/Glass.swift` (`.glass(in:)`, `.glassButton()`, `.glassProminentButton()`, `.drawOnTransition()`), never `glassEffect`/`.buttonStyle(.glass…)` directly. Any other newer API needs `if #available` with a plain fallback. Glass on chrome (sidebars, toolbars, panels, cards that float); values on opaque cool "paper" (`Color.paper`).
- Layouts from `docs/slinky-layouts.html`: A (.env project view), B (Library shelf), C (Quick Access ⌥⌘K), D (agent receipts, later), F (menu bar stack).
- Voice: see `VOICE.md`. Plain, serious, non-technical, for everyone. No clever labels in the app.
- **Design: read `docs/DESIGN.md` before any UI work.** It holds the principles, every reference and what we took from it, and decisions already made. No welcome screens or wizards (family rule).
