# Slinky — concept, architecture, and the brief + clickable mock

## Context

Derek ships two open-source native Mac apps: **Dinky** ("Dinky makes files smaller.", dinkyfiles.com) and **Binky** ("Binky sorts your files.", binkyfiles.com). **Slinky** completes the set. It's a local, native, free (MIT) Mac app for developer secrets: API keys, tokens, per-project `.env` variables and 2FA recovery codes. It's for solo founders and people building software with AI coding agents.

The problem:
- **Apple Passwords** is built around website logins. It has no API-key type, no custom fields, no secure notes and no CLI.
- **`.env` files** sit in plaintext in every repo. Claude Code, Cursor and Codex read them straight into their context and transcripts.
- **Recovery codes** end up as `.txt` files in Downloads.

Slinky should be the pleasant, HIG-native fix: a real Mac app, plus a `slinky` CLI and an MCP server, so agents can **use** secrets without ever **seeing** them.

## Decisions (Derek, 2026-09-24)
- **Next deliverable:** a brief plus a clickable UX mock, as one private, shareable page. The Swift scaffold comes after UX sign-off.
- **Tagline:** "Slinky keeps secrets out of files." Domain: **slinkyfiles.com**.
- **Minimum macOS:** 15 Sequoia (from 1.1; 1.0 required 26 Tahoe), Apple silicon. Liquid Glass on Tahoe, the standard frosted look on Sequoia (2026-10-17, to reach more developers).
- **No paid Apple Developer account yet.** Plan a fallback that ships without one; a Developer ID later is an upgrade, not a rewrite.

## Positioning: what exists, where Slinky wins
- **Big players, all cloud-account based:**
  - 1Password: Electron, $3.99/mo. Environments mounts `.env` files through a FIFO, and its MCP server returns names only.
  - Bitwarden: Electron. Has an MCP server and the Agent Access SDK.
  - Proton Pass: `pass-cli` is paid-only.
  - Infisical, Doppler and Phase are team/production tools. Varlock and dotenvx are CLI/schema tools.
- **Small native Mac apps (2026):**
  - NoxKey: menu bar only, CLI and MCP, AGPL. No main window and no recovery codes, and its GitHub repo returned a 404.
  - PassStore: MIT, SwiftUI. No CLI or MCP.
  - KeyStack and SecretKit: closed source.
  - Secretive: SSH keys only, but it's the trust and UX reference: names the process behind each request, notifies on every access, MIT, attested builds.
- **Apple:**
  - Passwords is unchanged for dev secrets in macOS 27 "Golden Gate" (shipped Sept 14, 2026).
  - Keychain Access is hidden and can no longer create secure notes.
- **Slinky's edge:**
  1. A main-window-first native app in the Dinky/Binky family: free, MIT, tiny, no dependencies.
  2. **Recovery codes as a first-class item:** click to copy and mark used, "7 left", a low-codes nudge, and a printable kit. The positioning: *your recovery codes live apart from your passwords*.
  3. **Agent flows done right:**
     - The agent sees names only.
     - A missing key gets pasted into a native Slinky sheet, *not the chat*.
     - Each request shows who's asking and needs Touch ID.
     - Grants are scoped and expire.
     - Everything goes in an activity log.
  4. **Exact-match leak detection.** Slinky knows the real values, so it can find them in staged git diffs, `~/.claude/projects/*.jsonl` transcripts, shell history and MCP configs, with no regex guessing.
  5. **A Secretive-level trust story:** no dependencies, attested builds, a public threat model, and the only network call is an opt-in update check.

## Brand and voice
- **Metaphor:** to *slink* means to move quietly so nobody notices. Secrets slip into your apps when they're needed and slip back out. Three words: **quiet, sly, kept.**
- The register is the same as Dinky and Binky: dry, warm, one-liners, no exclamation points, Slinky is the actor.
- **Hero:** "Keys under the doormat? Meet Slinky." (after Binky's "Fussy inbox. Meet Binky.")
- **Lines:**
  - Empty state: "Nothing to hide. Yet."
  - Recognition chip: "Looks like a Stripe live key."
  - Import done: "Tucked away 12. The .env can go." Buttons: "Move to Trash" / "Keep It for Now".
  - Missing-key request: "Claude Code needs RESEND_API_KEY. Paste it here, not in the chat."
  - Approval: "Claude Code wants 3 keys for `npm run dev`."
  - Copy: "Copied. Slinks off in 60s."
  - Denied: "Denied. Nothing slipped out."
  - Low codes: "3 codes left. Time for fresh ones."
  - Stats line: "38 keys · 6 projects · 0 lying around"
- **Avoid:** "military-grade", AES jargon in the UI (keep it on the How-it-works page), "credentials", "workflow".
- **Icon:** the family recipe (a saturated gradient with a chunky white sticker object, heavy black outline, slight tilt). Here it's a coiled spring with one coil threaded through a key ring.
  - **Brand (updated 2026-10-16): clear, glassy, white, clean, sleek.** The family reads blue · pink · clear. The icon (picked 2026-10-16) is one big frosted-glass asterisk with a rounded keyhole (K2, enlarged) recessed through its center. It is lit from the upper left with a crisp rim, a tight inner shadow and a soft drop shadow, on a pale ice-blue gradient. Dark mode is smoky slate on cold near-black. Sources: `design/icon/slinky-icon-keyhole-light.svg` and `-dark.svg`, generated by `design/icon/directions/make_final.py`. In Icon Composer: background layer, asterisk layer (glass on), keyhole layer. Sources: `design/icon/slinky-icon-ice-light.svg` and `-dark.svg`. The accent is a quiet ice blue (#4a7aa3 light, #a9c7dc dark). Avoid saturated blue. **Superseded 2026-10-17: glacier cyan, see `docs/DESIGN.md`.** Emerald is retired.
  - Built in Icon Composer with default, dark, clear and tinted variants.
  - Keep it clearly a key coil, not the toy's trade dress. "Slinky" is a class 28 toy trademark and software is class 9: low risk, same situation as Binky, not legal advice.

## Product

**Objects**
- **Key**: a standalone API key or token. It can be *linked* into many projects: rotate it once and every project gets the new value.
- **Project**: linked folder(s) and variables (secret or plain; `NEXT_PUBLIC_*` counts as plain). Environments are optional; the default is Local.
- **Recovery Codes**: one per account, with used state and a regenerated-on date.
- **Kept**: the catch-all for anything a site tells you to "store somewhere safe": a recovery key, setup key, license key, master or backup password, or a one-off token. Fields: label, "from" (site or app), the value, optional note and date. Paste detection still suggests the type ("Looks like an Apple recovery key."). Added 2026-10-16 after hitting exactly this.
- *Later:* secret files (`.p8`, service-account JSON).

**Surfaces**
- **Main window**: three columns, per the HIG for hierarchies deeper than two levels.
  - Sidebar: *Library* (All · Keys · Recovery Codes), *Projects* (badge when something's missing), then Health · Activity · Recently Deleted.
  - List rows: provider monogram chip (no brand logos, no network), NAME, masked `sk_live_••••4f2a`, LIVE/TEST badge, "used 2h ago by Claude Code".
  - Detail pane:
    - Hover to peek, as in Passwords; LIVE keys need a click plus Touch ID.
    - Copy, Large Type, Copy Reference (`slinky://harvous/STRIPE_SECRET_KEY`).
    - Used by, History, and a Rotate… sheet (open the provider dashboard, paste the new key, every linked project updates).
  - Toolbar search with tokens.
  - Deleting is undoable (⌘Z) with no alert.
- **First-version acceptance test (Derek, 2026-10-16):** on one day Derek had a recovery key, a personal API token and an env secret, and nowhere to put them. One Tuck It Away paste each should land them in the right place without thinking: Kept (with the print nudge), Key (with an optional expiry), and a project variable (pick the project; `slinky run` injects it).
- **Tuck It Away (quick capture)**: one global shortcut, a menu bar item, and a Services / Share entry ("Tuck Away in Slinky"). Paste or type, give it a label, done in under ten seconds. That's the "this page says write it down" moment. It shows a one-time nudge to print a copy for things you'd need if your Mac died (recovery keys).
- **Quick Access palette**: floating panel on a customizable global hotkey. Default ⌥⌘K, since ⇧⌘Space is taken in macOS 27. ⏎ copies, ⌘⏎ copies the reference, ⌥⏎ shows Large Type. Unlocks inline with `LAAuthenticationView`.
- **Menu bar extra**: opt-in, and a real menu. Lock state and time left, pending requests, recent items, Quick Access…, Revoke Agent Access, Lock, Open Slinky, Settings….
- **Approval panel**: a non-activating floating card (macOS 14+ won't let a background app steal focus).
  - It shows the verified requester chain ("Claude Code › zsh › npm"), folder, command and key names.
  - Scope choices: Once · 1 Hour · Until Lock. Then Touch ID.
- **Sheets**: Import (review .env rows), Request (paste field with live detection), Rotate.
- **Onboarding is the empty state** (the Binky pattern and the HIG's interactive onboarding): *Drop a .env or project folder* · *Paste a key* · *Paste recovery codes*. Then dismissible banners ("Found 9 .env files in ~/Projects. Tuck them away?", "Connect your agents").
- **Settings**: General · Security · Agents · Command Line · Backup · About. Uses Binky's Window-scene `NavigationSplitView` of grouped Forms.
- **Help**: `Help.md` rendered in a window, as Binky does.

**HIG and delight rules**
- Springs are the motif (it's a spring toy): imported rows slink in with a stagger, and the copy chip does a small coil-bounce. All of it is gated on Reduce Motion.
- Glass on toolbars and controls only; rows and cards stay opaque. Test against macOS 27's transparency slider and Increase Contrast.
- Touch ID wording follows `biometryType` ("Unlock with Touch ID" or "Unlock with Password"). The `localizedReason` is short, describes the action, and leaves out the app name.
- Notifications never contain secret details.
- **Clipboard**: marked concealed and transient so clipboard managers skip it, kept off Universal Clipboard (`currentHostOnly`), and auto-cleared after 60 s only if `changeCount` hasn't changed.
- System sounds (Tink on copy, Pop on import) with a toggle. Rotating empty-state taglines.

## Agents: CLI and MCP
- **CLI (`slinky`)**: embedded in the app, linked by the cask's `binary` stanza or Settings → Install Command Line Tool. Parsing is hand-rolled; `--json` output uses `slinky.<cmd>/1.0.0` envelopes, human messages go to stderr.
  - `run [-p proj] -- argv…`: puts keys into the command's environment. Output is masked through a pty (exact values plus base64/hex/URL variants). This is labeled best effort.
  - `check`: missing names compared with `.env.example` or `.env.slinky`.
  - `ls`: names and metadata only.
  - `request NAME --why --url`: opens the native sheet and waits.
  - `link`, `import .env [--trash]`, `example`, `status`, `lock`.
  - `connect claude|cursor|codex|claude-desktop`.
  - `mcp`: the MCP server.
  - `read`: human terminals only. Touch ID every time; refuses when an agent is in the parent chain.
  - Values are never accepted in argv.
- **`.env.slinky`**: a committable file of `NAME=slinky://project/NAME` references.
- **MCP**: a hand-rolled JSON-RPC server over stdio that supports both the older `initialize` handshake and the 2026-07-28 spec's `server/discover`. The official swift-sdk is Tier 3, pre-1.0, and pulls in NIO and swift-log.
  - v1 tools:
    - `list_projects`
    - `list_secrets` (name, kind, provider, test or live, agent-usable)
    - `check_env`
    - `request_secret`: returns only prompted, added, declined or timeout. The reason is shown as agent-supplied and unverified, and requests are rate-limited.
    - `describe_policy`
  - Server instructions: run commands with `slinky run --`, and never ask for keys in chat.
  - Commands run through the **agent's own shell**, so the agent's sandbox and permission prompts still apply. MCP servers run outside those sandboxes, so a `run_with_secrets` tool with run handles waits for v1.x, for clients without a shell.
  - **Never exposed:** values, reveal, clipboard, export, writing `.env` files, `set_secret(value)`, delete or rotate, policy or approval changes, TOTP or recovery codes, and anything derived from a value (hash, length, prefix).
  - No elicitation form mode for keys; the spec forbids it. URL mode is only an optional extra.
- **Rules when an agent is asking:**
  - Touch ID for each command, showing the exact argv, the resolved executable and the folder.
  - A default deny list: `sh -c`, `node -e`, `python -c`, `env`/`printenv`, `curl`/`wget`/`nc`/`ssh`, `git push`, `npm publish`, `osascript`, `open`, `pbcopy`.
  - Approvals are bound to the executable's hash and to hashes of `package.json` scripts and Makefile targets.
  - `NODE_OPTIONS`, `DYLD_*`, `BASH_ENV` and similar are stripped.
  - LIVE keys are *not agent-usable* by default.
  - Everything is logged and triggers a notification.
- **Connect** (Settings → Agents): per tool, with a diff preview, a backup, and a Disconnect that reverses it.
  - Claude Code: `claude mcp add --scope user slinky -- <abs>/slinky mcp`, `permissions.deny` for `Read(./.env*)`, the socket path in `sandbox.network.allowUnixSockets`, and a CLAUDE.md snippet.
  - Cursor: `~/.cursor/mcp.json`.
  - Codex: `config.toml` plus `shell_environment_policy`.
  - Claude Desktop: config JSON with absolute paths.
- **Honest limits** (on the site as-is):
  - Approved commands get the key. An injected agent can still try to exfiltrate through an approved or edited script.
  - Values in a process's environment are readable by same-user processes (`ps -E`).
  - Masking isn't a boundary.
  - Root, and apps with Accessibility permission, can get around the prompts.
  - The line: "Slinky keeps secrets out of the model and off your disk. It isn't a sandbox."

## Architecture: one design, two signing tiers
- **Broker:** Slinky.app is menu-bar capable, launches at login (`SMAppService.mainApp`) and is the **only** process that decrypts anything. The CLI starts it if it isn't running.
- **Vault:** an AES-GCM file in `~/Library/Application Support/Slinky/` with versioned nonces and AAD. It holds keys, projects, codes and history, plus a separate encrypted activity log.
- **The vault key is wrapped twice:**
  - By a **Secure Enclave key** (CryptoKit `SecureEnclave.P256.KeyAgreement`, HPKE `P256_SHA256_AES_GCM_256`, flags `.privateKeyUsage` + `.userPresence`). This gives Touch ID with a password or Apple Watch fallback, and it's hardware-bound.
  - By a **Recovery Key**: a random 256-bit key shown once as a printable kit. "Print it or keep it in Apple Passwords. Never in Slinky." Backups and moving Macs use it.
  - Never use `.biometryCurrentSet`; a changed fingerprint would destroy the vault.
- **Session:** one evaluated `LAContext` is passed to each operation. Idle lock after 10 minutes, hard lock after 12 hours, and on sleep, screen lock, user switch or "Revoke Agent Access". `touchIDAuthenticationAllowableReuseDuration` is *not* a session.
- **Transport:** a Unix domain socket in the 0700 app-support directory. On each connection:
  - read the peer's audit token (`LOCAL_PEERTOKEN`) and get its code object (`SecCodeCopyGuestWithAttributes`)
  - check its code-signing requirement
  - walk the parent processes with `proc_pidinfo`/`proc_pidpath` to build "who's asking"
  - Environment markers (`CLAUDECODE`, `CURSOR_AGENT`, `CODEX_SANDBOX`) are hints only.
  - Agent sandboxes can allowlist Unix sockets (Claude Code, Codex); Codex can't allowlist XPC.
- **Tier 1 — ships now, no Developer ID:**
  - Sign with a **stable self-signed code-signing identity**, so the code-signing identity (designated requirement) doesn't change between updates. Keychain approvals and permissions then survive updates, unlike ad-hoc signing.
  - The Secure Enclave key's blob goes in a **legacy login-keychain item whose access list trusts only Slinky**. Other processes can't read it silently; they'd trigger a prompt with their own name.
  - Apple DTS calls using the Secure Enclave without a provisioning profile unsupported. It works in practice (age-plugin-se does it), and the Recovery Key means a future macOS change can never lock anyone out.
  - Hardened runtime on and no `get-task-allow` in Release builds.
  - Built on GitHub Actions (macos-26) with `attest-build-provenance`, so anyone can run `gh attestation verify`. Releases are signed with Slinky's own Ed25519 key, which the updater checks before swapping the app.
  - Install instructions say plainly how to use Open Anyway. **Homebrew 5 removed `--no-quarantine`**, so cask users will see the Gatekeeper block.
  - While developing, sign with your **free Apple ID (Xcode Personal Team)** to try the supported path on your own Mac.
- **Tier 2 — with a Developer ID** (the vault, approvals, CLI and MCP don't change):
  - Notarization.
  - The Secure Enclave blob moves to the data-protection keychain.
  - The broker becomes a `SMAppService.agent` with XPC (`XPCPeerRequirement`), keeping the socket for sandboxed agents.
  - Optional CloudKit sync, encrypted before it leaves the Mac.
- **Sync in v1:** this Mac only, plus a backup export protected by the Recovery Key (the vault file is Time Machine-safe as is).

## Roadmap
- **v1.0**
  - Vault, unlock and auto-lock, Recovery Key, backup export
  - Keys, Projects and Recovery Codes, with Recently Deleted
  - Main window, Quick Access, menu bar
  - Paste detection from gitleaks-derived rules (MIT; not TruffleHog, which is AGPL)
  - .env and folder import with Move to Trash
  - Clipboard hygiene
  - CLI, MCP (v1 tools) and Connect
  - Approvals and Activity
  - Tier 1 distribution and the slinkyfiles.com site
- **v1.x**
  - Leak radar (exact match, a git pre-commit guard, rotation checklists)
  - Health view, expiry and rotation reminders, value history
  - MCP `run_with_secrets` with handles
  - App Intents/Spotlight actions, and a Control Center control for "Lock / Revoke agent access"
  - Secret files (materialized as temp files, mode 0600)
  - Binky handoff: "Looks like recovery codes." → Give to Slinky
  - Apple Passwords CSV import
- **Later**
  - Tier 2 (Developer ID)
  - CloudKit sync
  - Claude Code `sandbox.credentials` mask bridge
  - Opt-in FIFO `.env` mounting
  - TOTP (maybe; Passwords already does it well)
  - iPhone companion for recovery codes

## Next step (what I'll do after approval): the brief + clickable mock
1. Run `Artifact` quickstart (intent "other"), then load the `artifact-design` skill, plus `artifact-diagramming` for the architecture diagram.
2. Write one self-contained HTML page, `slinky-brief.html`, in the scratchpad. Publish it as a private Artifact (icon "key", title "Slinky Brief") and share the link.
3. **Page outline:**
   - Hero: an SVG coil-and-key-ring sticker icon on emerald, the tagline, and a Dinky · Binky · Slinky family strip.
   - Why: three problem cards.
   - **The mock.**
   - Voice table.
   - How it works: an SVG diagram (Agents → `slinky`/`slinky mcp` → socket → Slinky.app + approval → vault ← Secure Enclave / Recovery Key), plus the two-tier table.
   - What exists: a comparison table.
   - Honest limits.
   - Roadmap.
   - Open questions: Developer ID timing, pricing and the family bundle, TOTP, sync.
4. **Mock:** a macOS Tahoe window with a scene switcher. Every scene is clickable:
   - **Welcome**: empty state, then "Drop a .env", then an import sheet with detection chips, then rows spring in, then the "Tucked away 9…" toast with Move to Trash / Keep It for Now.
   - **Keys**: the three-column window, hover-to-peek, Copy with a 60 s countdown toast, Copy Reference, Used by, and a Rotate… sheet.
   - **Recovery Codes**: 10 chips; clicking one copies it, strikes it through and updates "7 left"; Undo; a low-codes nudge at 3; Print Kit.
   - **Agent asks**: a mini terminal runs `slinky run -- npm run dev`, then the approval card slides in (requester chain, folder, keys, scope segments), then Touch ID, then masked output. There's also a Deny path.
   - **Paste, not chat**: an agent transcript asks for RESEND_API_KEY, then Slinky's sheet appears, typing `re_` shows "Looks like a Resend key.", then "Tuck It Away", then the agent says "Added. I never saw it."
   - **Quick Access**: the palette with live filter; ⏎ copies.
   - **Menu bar**: the dropdown menu.
5. **Constraints:**
   - Obviously fake values (e.g. `sk_live_EXAMPLE…`).
   - Monograms instead of brand logos.
   - Real buttons and keyboard access.
   - `prefers-reduced-motion` respected.
   - Light and dark themes via CSS tokens.
   - The mock scales to fit at phone width with no horizontal scroll.
   - No external assets beyond an allowed CDN if needed.

## Later: repo scaffold (after UX sign-off; a new `~/slinky`, sibling of `~/binky`)
- **Base it on Binky.** Bring in these improvements from Dinky:
  - `DinkyRootModel.shared`
  - `SceneOpener`
  - `Dinky/Services/DockPresenceManager.swift`
  - `Dinky/Services/GlobalHotkeyManager.swift` (Carbon)
  - the App Intents that return results
  - the package `.testTarget` and `DinkyCLILibTests/JSONContractTests.swift`
- **Copy and rename:**
  - `binky/BinkyCore/Package.swift` becomes the `SlinkyCore` package, targets: Shared · Vault · CLILib · CLI; swift-tools 6.0.
  - `Binky/BinkyExportedDependencies.swift`
  - `Binky/Extensions/View+AdaptiveGlass.swift`
  - `Binky/Views/SettingsChrome.swift`
  - the `Binky/Strings.swift` pattern
  - the `PreferencesView` skeleton, split into per-pane files
  - `Models/CustomShortcut.swift` and `Views/ShortcutRecorderField.swift`
  - `Views/HelpWindow.swift` and `Resources/Help.md`
  - `Services/LaunchAtLoginManager.swift`
  - Dinky's `DiagnosticsReporter.swift`
  - Binky's CLI Bootstrap/Parse/Print/Help files
  - `release.sh` (merge in Dinky's preflight tests; add attestation and Ed25519 signing)
  - `Casks/`
  - `.github/workflows`
  - the xcstrings setup
  - `AppIcon.icon`
  - the whole of `site/`, and add a third tab to the dinkyfiles and binkyfiles tab strips
  - `CLAUDE.md`, `agents.md`, `VOICE.md`, plus new `SECURITY.md` and `docs/threat-model.md`
- **Don't copy:**
  - the compression engines and `bin`/`lib`
  - `DinkyServeCommand` (it listens on all network interfaces; a separate fix chip is up)
  - the updater as it stands (it doesn't verify signatures)
  - Binky's CLI prefs store that uses `.standard` defaults
  - the sort-specific services

## Verification
- **Mock:**
  - Open it in the built-in browser.
  - Click through every scene and interaction.
  - Check desktop and the mobile preset, light and dark (`colorScheme`), keyboard-only use and Reduce Motion.
  - Confirm there are no console errors.
  - Then publish privately and confirm the link loads.
- **Scaffold (later):**
  - `xcodebuild … test` and `swift test` pass.
  - An MCP conformance run passes, plus a scripted stdio handshake: `server/discover`, `initialize`, `tools/list`.
  - `slinky run -- printenv` shows masked output.
  - A peer-check test where an unsigned client is rejected.
  - A lock/unlock and Recovery Key round trip.

## Notes added 2026-10-16 (macapp.supply design pass)
- **Unwind** (on macapp.supply) is a neighbor, not a competitor. It "clears what coding agents leave behind": CLI + MCP, €14.99 one-time, macOS 26+. It supports the ~$15 Pro price. Borrow its "a reason for every suggestion" pattern for the Health view. A possible cross-promotion.
- **Layouts added:**
  - **E · Rising Shelf:** Quick Access as a bottom-edge glass shelf, after Supaste. C stays the default; E is the challenger.
  - **F · Menu bar stack:** live glass cards, after DisplayBuddy.
  - **G · Glance widget:** v1.x.
  - All in `docs/slinky-layouts.html`.
- **Site headline style:** big stacked declaratives in the family voice ("Paste it. Tuck it. Forget it.").
- **Quick Access hotkey:** ⌥⌘K. Not ⌃⌥Space, which macOS uses to switch input sources, and not ⇧⌘Space, which macOS 27 uses for Visual Intelligence.

## Idea: the "working" animation (Derek, 2026-10-16)
While Slinky is busy, the keyhole is absorbed into the asterisk (it scales and fades into the hub), then the asterisk spins. When the work finishes, the spin eases out with a spring and the keyhole reappears.
- **Where:**
  - unlocking (waiting for Touch ID)
  - an agent's `slinky run` in progress
  - Quick Access and Tuck It Away while saving
  - the menu bar asterisk while any agent session is active
- **How:** in SwiftUI it's `KeyholeMark(isWorking:)`, with keyhole scale and opacity going to 0 and a repeating rotation on `AsteriskShape`. The menu bar gets a template-image version of the same frames.
- **Rules:** honor Reduce Motion (keyhole fade only, no spin). Never spin while idle.


## Integrations (decided 2026-10-17)
- **Shortcuts (built):** Add to Slinky (opens Add Item prefilled; pair with Get Clipboard for "Save clipboard to Slinky"), Copy from Slinky (Touch ID every time, never returns the value), Open Quick Access, Lock Slinky. Items show by name only while unlocked.
- **Raycast (with the agents milestone):** a small open-source Raycast extension that calls the `slinky` CLI: search items by name, copy (goes through the same approval and Touch ID rules as agents), add from clipboard, lock. It has to wait for the CLI and socket broker, which are what keep values from flowing through Raycast's own process. Raycast would show up in receipts like any other caller ("Raycast › slinky").
- **Clipboard managers:** everything Slinky copies is marked concealed and transient (`org.nspasteboard.ConcealedType` / `TransientType`), so Raycast's clipboard history, Paste, Maccy and similar skip it, and it clears after 60 seconds. Worth saying on the site.


## v1.0.0 status (2026-10-17)
Built: vault with Touch ID and Recovery Key (and making a new one), Keys & Tokens, Recovery, Projects with folder scan/.gitignore check/.env.example, Add Item and New Project panels, editing everything, Needs Attention, search, Quick Access ⌥⌘K, menu bar, Shortcuts actions, Settings (lock timing, clipboard timing, menu bar, open at login, sounds), Help, project export (Copy as .env, Save .env.example), release script, DMG/zip, Homebrew cask.
Before publishing: Derek's real-use test (his recovery key, personal token and .env secret), a light-mode pass, and a GitHub remote.
Next milestone (v1.1): the agents work (slinky CLI with masking, socket broker, approval cards, receipts, MCP, Connect for Claude Code), then Raycast.
