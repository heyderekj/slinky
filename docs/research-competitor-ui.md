# Competitor UI, user feedback and macOS 26/27 patterns

*Research as of 2026-10-16. User feedback is paraphrased; follow the links for exact wording. Items marked "unverified" had thin sources.*

## 1. Competitor teardown

### Password managers

**Apple Passwords (macOS 15, 26 Tahoe, 27 Golden Gate)** — native SwiftUI.
- **Layout:** three columns. Sidebar categories: All, App, Website, Sign in with Apple, Passkeys, Verification codes, Wi-Fi, Shared groups ([Apple](https://support.apple.com/guide/passwords/the-passwords-app-mchl901b1b95/mac)).
- **Reveal and copy:** hover over the dots to reveal ([Apple](https://support.apple.com/guide/passwords/see-a-password-mchl37e45d7c/mac)). Tahoe moved the FileVault recovery key into Passwords, with hover-to-reveal and click-to-copy ([Apple](https://support.apple.com/guide/passwords/filevault-recovery-key-mchl307c4fa9/mac)). That's Apple's own precedent for "keep this safe" items.
- **Menu bar extra:** off by default; a mini app with search and an add button ([Apple](https://support.apple.com/guide/passwords/menu-bar-mchldd5eb88d/mac)). Right-click copies ([Tsai](https://mjtsai.com/blog/2024/07/19/apple-passwords-app-in-sequoia-and-ios-18)).
- **Recent additions:** password history in Tahoe ([MacMost](https://macmost.com/password-history-on-mac-and-iphone.html)). AI auto-fix of weak passwords in 27, after the user approves ([BleepingComputer](https://www.bleepingcomputer.com/news/apple/new-apple-feature-automatically-changes-your-compromised-passwords/amp/)).
- **Gaps:** no attachments, no secure notes, no custom fields, no folders or tags, weak keyboard navigation, no drag-out.

**1Password 8** — Electron with a Rust core, "Knox" design.
- **Layout:** sidebar (accounts/vaults, categories, tags, Watchtower, Developer), then list, then detail ([BetaNews](https://betanews.com/2022/05/04/1password-8-for-mac)).
- **Quick Access:** a floating palette, moved to ⌥⌘\ on macOS 27 ([1P](https://www.1password.community/announcements-52/the-quick-access-shortcut-is-changing-in-macos-golden-gate-25559)).
- **Developer → Environments** ([1P blog](https://1password.com/blog/1password-environments-env-files-public-beta), [Flavio Copes](https://flaviocopes.com/1password-environments)):
  - import a .env file; values hidden by default;
  - mount a virtual .env over pipes, at most 10 per device;
  - Developer Watchtower finds plaintext .env files.
  - Weakness: once authorized, the mount serves any process.
- **API Credential item:** the default "Username/Credential" labels confuse people ([1P](https://www.1password.community/1password-at-work-58/my-feature-wish-list-22082)).

**Bitwarden desktop** — Electron, three panes.
- **2026.1 redesign:**
  - folders collapsed by default;
  - Import/Export moved into the sidebar;
  - middle column can't be resized ([forum](https://community.bitwarden.com/t/desktop-2026-1-0-remove-ui-clutter/94052)).
- **2026.4:**
  - looser spacing;
  - only the title is clickable;
  - copy shortcuts removed;
  - Ctrl+F no longer opens search ([forum](https://community.bitwarden.com/t/desktop-app-2026-4-0-usability-feedback-and-bugs/96908)).

**Proton Pass** — three panes (vaults+trash | items | details). Pinned items, 2FA codes, email aliases ([Proton](https://proton.me/support/use-pass-web)). Its desktop app is web-based (unverified), and users raise memory concerns.

**KeePassXC** — Qt. A group tree plus an entry table with configurable columns; double-click a cell to copy. Looks conservative, and VoiceOver has problems ([AppleVis](https://applevis.com/comment/208792)).

**Strongbox** — native, praised for that versus Electron rivals. Sold to Applause Group, which some users view with scepticism ([Setapp](https://setapp.com/apps/strongbox/customer-reviews)).

**Enpass** — a glass-style refresh in November 2025 ([Enpass](https://www.enpass.io/blog/announcement/a-new-look-for-enpass-built-around-you/)). **Dashlane** — dropped its Mac app in 2022 for web plus extensions ([Dashlane](https://www.dashlane.com/blog/dashlane-web-first)).

### Developer-secret apps

**Secretive** — native.
- Shows key fingerprints and an "agent running" indicator.
- Touch ID or Watch can be required per key, and a **notification fires on every key use**.
- Keys can't be exported; setup is technical ([GitHub](https://github.com/maxgoedjen/secretive)).

**NoxKey** — SwiftUI menu bar app plus CLI and MCP ([site](https://www.noxkey.ai/), [dev.to](https://dev.to/jaspernoboxdev/noxkey-a-macos-secrets-manager-with-touch-id-and-ai-agent-detection-fon)).
- **List:** filter field on top; rows grouped by `org/project` with type badges and a masked prefix.
- **Copy and peek:** clipboard clears after 30 seconds; `peek` shows the first 8 characters.
- **Access levels per secret:** easy, normal, strict, off-limits.
- **Quick panel:** ⌘⇧1.
- **Agent handling:** detects agents via the process tree. There's **no visual approval card**.

**Keyholdr** — menu bar app on ⌃⌥⌘K. Touch ID on every copy; grouped by platform and tags; `keyholdr run` ([Product Hunt](https://www.producthunt.com/products/keyholdr)).

**PassStore, SecretKit** — low traction, and their UI is undocumented (unverified).

### Dev dashboards

- **Doppler:** project → environments → configs; an unsaved-changes banner; change requests with approvals ([docs](https://docs.doppler.com/docs/root-configs)).
- **Infisical:** a **Secrets Overview matrix** across environments that flags missing or empty keys; drag-drop import of .env and similar ([docs](https://infisical.com/docs/documentation/getting-started/platform)).
- **Vercel:** an "Add New" form above the list. Since 2026, **Config (readable) vs Secret (write-only)** ([docs](https://vercel.com/docs/environment-variables)).
- **Railway:** a RAW .env editor; **suggested variables read from `.env.example`**; `${{ }}` references; **sealed** variables; staged changes ([docs](https://docs.railway.com/guides/variables)).

### Non-secrets references

- **Raycast:** one field plus a list. ↵ runs the primary action, ⌘↵ the secondary, ⌘K opens an action panel ([manual](https://manual.raycast.com/action-panel)).
- **CleanShot X:** a floating thumbnail after each capture that you can stack, pin and drag ([Macworld](https://www.macworld.com/article/617854/cleanshot-x-review.html)).
- **Things 3.22:** a roomier, more transparent glass sidebar.
- **macOS 27 Mail and Finder:** edge-to-edge sidebars with colored icons, and uniform toolbars ([Six Colors](https://sixcolors.com/post/2026/09/macos-27-golden-gate-review-bridging-the-tahoe-gap/)).

## 2. User feedback by theme

- **A. Non-native Electron feel (very common).**
  - 1Password 8's "non-native feel" thread has 127+ replies: no rubber-band scrolling, weak focus cues, worse single-click copy ([1P](https://1password.community/discussion/comment/608906/), [Tsai](https://mjtsai.com/blog/2022/05/03/1password-8-for-mac)).
  - Bitwarden takes minutes to load on Tahoe on an M1 ([forum](https://community.bitwarden.com/t/bitwarden-desktop-app-extremely-slow-on-macbook-air-m1-macos-26-0-1/90053)).
- **B. Too many clicks and lost shortcuts (common).** The Bitwarden 2026.1 and 2026.4 backlash: spacing, title-only click targets, multi-click copy.
- **C. Quick Access copies the wrong thing (occasional to common).**
  - Search opens the previously viewed item ([1P](https://www.1password.community/1password-at-home-31/quick-search-opens-to-incorrect-login-card-in-the-app-3656)).
  - Shortcuts copy the previously selected item ([1P](https://www.1password.community/1password-at-home-31/search-then-copy-using-shortcuts-copies-the-previously-selected-item-s-password-16069)).
- **D. Recovery codes have no home (common, 2021–2026).** Six or more 1Password threads ask for a type with masked codes, one per row, mark-as-used and a generation date ([2025](https://www.1password.community/1password-at-home-31/feature-request-dedicated-backup-codes-item-type-in-1password-22660), [May 2026](https://www.1password.community/1password-at-home-31/feature-suggestion-recovery-codes-info-type-for-records-24560)).
- **E. Item types don't fit developer secrets (growing).** Requests for an API Key type with environment, expiry, rotation and scopes ([1P](https://www.1password.community/developers-69/new-item-type-recommendation-api-keys-23306)).
- **F. Apple Passwords is too thin (common).** No attachments, drag-out, folders or tags, and weak keyboard navigation. It is still praised as Apple's best-feeling SwiftUI app ([Tsai](https://mjtsai.com/blog/2024/07/19/apple-passwords-app-in-sequoia-and-ios-18)).
- **G. AI agents reading .env files (very common in 2025–26).** [The Register](https://www.theregister.com/2026/01/28/claude_code_ai_secrets_files/), [Knostic](https://www.knostic.ai/blog/claude-cursor-env-file-secret-leakage).
- **H. Tahoe glass legibility (very common).** See §3.

## 3. macOS 26/27 patterns and legibility

**Apple's guidance:**
- **Materials** ([HIG](https://developer.apple.com/design/human-interface-guidelines/materials)):
  - Liquid Glass for the navigation and control layer only, with content on standard materials.
  - Regular glass for text-heavy pieces; clear glass only over rich media, with dimming.
  - Use glass sparingly, and respect Reduce Transparency and Increase Contrast.
- **Sidebars** ([HIG](https://developer.apple.com/design/human-interface-guidelines/sidebars)): at most two levels; nothing critical at the bottom; auto-collapse in narrow windows.
- **WWDC25 sessions** ([356](https://developer.apple.com/videos/play/wwdc2025/356/), [323](https://developer.apple.com/videos/play/wwdc2025/323/)):
  - fixed, capsule and concentric shapes;
  - group toolbar items by function, with the primary action set apart and tinted;
  - scroll edge effects instead of dividers;
  - `GlassEffectContainer`, since glass can't sample glass;
  - `.inspector`, and `.searchable` at the top trailing edge.

**What changed in 26.x and 27:**
- **26.1:** a Clear vs Tinted glass toggle ([Eclectic Light](https://eclecticlight.co/2025/11/05/appearance-revisited-get-tahoe-26-1-looking-in-better-shape/)).
- **Tahoe Spotlight:** app actions plus Quick Keys ([TechCrunch](https://techcrunch.com/2025/06/09/apple-updates-spotlight-to-take-actions-on-your-mac/)).
- **Tahoe Control Center:** third-party controls that can be pinned to the menu bar ([9to5Mac](https://9to5mac.com/2025/06/28/new-macos-tahoe-feature-solves-common-complaint/)).
- **macOS 27:**
  - a transparency slider;
  - **sidebars edge-to-edge again, not floating**, with colored icons;
  - uniform toolbars; clearer active-window state; icons in menus.
  - Sources: [MacRumors](https://www.macrumors.com/2026/06/09/macos-golden-gate-liquid-glass/), [Six Colors](https://sixcolors.com/post/2026/09/macos-27-golden-gate-review-bridging-the-tahoe-gap/).
- **Implication:** use the system split view, and don't build the look around a floating inset sidebar.

**Critiques of Tahoe's glass:**
- Howard Oakley: bleached-white Light Mode where edges disappear ([Eclectic Light](https://eclecticlight.co/2025/12/28/last-year-on-my-mac-look-back-in-disbelief/)).
- Gruber, Mueller and Johnson on illegible menus, white backgrounds and faint selection ([Tsai](https://mjtsai.com/blog/2025/12/29/)).
- NN/g on trading usability for spectacle.
- LCD screens show translucency worse than OLED.

**Rules for Slinky's glass:**
1. Glass only on chrome: sidebar, toolbar, quick panel, approval card.
2. Values sit on an opaque "paper" surface in monospace at ≥4.5:1 contrast.
3. Prevent whiteout with hairline borders, soft shadows and a slightly cooler ice-tinted content area.
4. Use the tint once per view, for the primary action.
5. Test both ends of the 27 slider, Clear/Tinted, Reduce Transparency, Increase Contrast, and an LCD.
6. Never put glass on glass.

## 4. Opportunities
1. **One-paste capture that routes by type** (`sk-…`, `ghp_…`, `AKIA…`, `otpauth://`, a block of codes, `KEY=VALUE` lines).
2. **Project-first layout that mirrors .env**, with an environment-columns toggle and missing/empty dots, Infisical-style.
3. **Recovery codes as a chip grid:** strike-through when used, an "N left" count, the generation date.
4. **A "Keep Safe" shelf for one-off items**, following Apple's FileVault-key precedent.
5. **Agent approval as a floating glass card:** agent, folder, key, scope, Touch ID; stacks like CleanShot.
6. **An access receipts timeline** for each key.
7. **Sealed, agent-only keys** (Vercel Secret, Railway sealed, NoxKey off-limits).
8. **A Raycast-grade palette** that always previews the *selected* item, so nothing is copied by mistake.
9. **Peek and fingerprint** (`sk-…4f2a`) instead of a full reveal.
10. **A visible clipboard countdown ring.**
11. **.env drift check** against `.env.example`, Railway-style.
12. **Quiet expiry and rotation tags.**
13. **Spotlight Quick Keys and a Control Center "pause agents" control.**
14. **Native density:** whole rows clickable, full keyboard navigation, copy shortcuts that never regress.
15. **Empty states that teach by doing:** the drop zone is the empty state.

## Addendum: second pass (same day)

**Corrections**
- **NoxKey does show an approval card.** Over MCP it names the agent, the key and the calling process, and the agent gets a self-deleting `source` script, never the raw value ([blog](https://noboxdev.com/blog/mcp-server-secrets-management)).
- **Secretive 4.0 has a pending-requests view** that batches requests from the same process. One user found it hidden behind other windows because the app has no Dock icon ([PR #821](https://github.com/maxgoedjen/secretive/pull/821)). Slinky's approval cards must always be frontmost.

**New references**
- **Proton Pass "Other" templates:** 14 types, including API Credential, SSH Key and Database ([Proton](https://proton.me/support/create-custom-item)).
- **Bitwarden:** no new item types planned ([forum](https://community.bitwarden.com/t/additional-item-types-pre-defined/228?page=15)).
- **Doppler Compare** (July 2026): groups secrets by value across environments ([blog](https://www.doppler.com/blog/compare-secrets-across-environments)).
- **secretctl:** output redacted to `[REDACTED:KEY]`, plus a tamper-evident audit log ([GitHub](https://github.com/forest6511/secretctl)).
- **Proton Pass Touch ID MCP:** the prompt shows the agent's stated reason ([GitHub](https://github.com/seliem-attia/proton-pass-touchid-mcp)).
- **KeyStack** (unverified): environment diff, an expiring `.env.local`, and "Needs Rotation" badges.
- **Sketch "Copenhagen":** tried floating glass panels, then chose fixed sidebars ([Tsai](https://mjtsai.com/blog/2025/11/20/sketch-copenhagen/)).
- **Photos on macOS 27:** a real toolbar bar instead of floating buttons.

**Extra opportunities**
- **Agent policy per key** as a three-way control: "Agents can use / Ask every time / Never leaves Slinky". This maps Vercel's Config/Secret split, NoxKey's levels and Doppler's visibility settings onto one control.
- **Category tiles with counts** at the top of the sidebar, Apple and Reminders style (Keys, Codes, Kept, Requests), with projects below to keep the hierarchy at two levels.
- **Always Regular glass, never Clear.** Slinky has no media to sit over.
- **Ice blue for fills, deep blue for text** at 4.5:1 or better. Monospaced secret values reach 7:1 on solid surfaces.
- **The menu bar extra can be hidden in the macOS 27 overflow,** so pending-request badges also need a notification and a Dock badge.
