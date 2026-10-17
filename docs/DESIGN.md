# Slinky — design principles and references

Read this before any design work. Every visual decision should trace back to something here. If it doesn't, decide on purpose and add it.

## Principles
1. **Intentional and tasteful over busy.** Each screen has one job and one primary action. When in doubt, remove.
2. **Native Tahoe first.** Use system components (`NavigationSplitView`, inspector, toolbar, sheets, glass buttons) before inventing. Custom only where Slinky has something to say: the `.env` view, recovery-code chips, Quick Access, approval cards.
3. **Glass on chrome, paper under values.** Liquid Glass belongs to sidebars, toolbars, floating panels, menu bar cards and toasts. Secret values always sit on opaque cool paper (`Color.paper`), in monospace, at 4.5:1 contrast or better. Never glass on glass.
4. **Ice, not blue.** The brand is clear, glassy and white, with glacier/ice blue. Accent `#4a7aa3` in both light and dark mode (Derek, 2026-10-17), used once per view on the primary action. It's deep enough for white text (about 4.6:1), which macOS uses on sidebar selections, menus and prominent buttons. The old pale dark accent (`#a9c7dc`) failed that (Derek, 2026-10-17); ice stays in the icon, backdrop and tints. No saturated blue in UI chrome.
5. **The family way of teaching.** Like Dinky and Binky, there's **no welcome screen and no wizard**. The app opens into itself. Empty states teach by doing ("No items yet. Add your first item with ⌘N."), and setup happens in context (the vault is created on the first save, and the Recovery Key appears right then as a sheet).
6. **Calm motion.** Springs, not bounces for their own sake. Motion explains a change (things slink in and out). Everything honors Reduce Motion.
7. **Plain, serious copy.** See `VOICE.md`. Clear and kind for everyone, non-technical first, no clever labels or wordplay in the app, no exclamation points, no fear.

## Before shipping any UI change
- Check light and dark, both ends of the macOS 27 transparency slider, Reduce Transparency, Increase Contrast and Reduce Motion.
- Check on a non-Retina or LCD screen if possible. Glass reads worse there.
- Keyboard only: can you do it without the mouse?
- VoiceOver labels on anything masked ("Hidden value, ends in 4f2a").
- Does it still look like the same family as Dinky and Binky?

## References, and what we take from each
| Reference | What we take | Where it shows up |
|---|---|---|
| **Dinky / Binky** (`~/dinky`, `~/binky`) | Contextual banners instead of onboarding; empty states that teach; Window-scene Settings with a `NavigationSplitView` and grouped Forms; transparent title bar (Binky's `TransparentWindow`); the family voice. The sticker icon recipe inspired our first icons. | App structure, `TransparentTitlebar`, empty states, `VOICE.md` |
| **Apple Passwords** | Hover-to-reveal, click-to-copy codes, sidebar category tiles with counts, the opt-in menu bar mini app | `RevealField`, `CategoryTile`, menu bar |
| **macOS 26/27 system apps** (Mail, Finder, Photos, Reminders) | Edge-to-edge sidebars in 27, uniform toolbars, tiles with counts, a real toolbar over content | `MainView` |
| **Raycast** | ↵ / ⌘↵ / ⌘K action model, one field plus a list | Quick Access |
| **1Password Quick Access** (anti-reference) | Users paste the wrong item because the selection is ambiguous. We always preview exactly what Return copies. | Quick Access preview pane |
| **CleanShot X** | Floating stacked thumbnails | Agent approval cards (layout D) |
| **Secretive** | Notify on every key use, honest limits up front, trust story | Receipts, docs |
| **Infisical / Railway / Vercel** | Environment matrix with missing dots; `.env.example` suggestions; sealed write-only values | `ProjectView` (layout A) |
| **macapp.supply: Supaste** | Bottom-edge glass shelf with pill tabs and counts | Layout E (Rising Shelf) |
| **macapp.supply: DisplayBuddy** | Menu bar popover as stacked translucent cards | `MenuBarStack` (layout F) |
| **macapp.supply: Cooldock** | Live widget tiles | Layout G (widget, v1.x) |
| **macapp.supply: Trailback** | Clean white app UI; stacked declarative headlines ("Find it. Sort it. Tidy it.") | Site headline style |
| **macapp.supply: Glance** | Minimal chrome, typography forward | Restraint in general |
| **macapp.supply: Unwind** | "A reason for every suggestion" | Health view (v1.x) |
| **Helium browser icon** (caution) | A white asterisk on deep blue. Ours must stay distinct: glacier blue (not indigo), tilt, keyhole. | App icon |

## Decisions already made
- **Icon:** a glass asterisk with a rounded keyhole (K2, enlarged) on glacier blue. Real Liquid Glass via `Slinky/AppIcon.icon` (asterisk layer with glass on, keyhole layer on top, automatic gradient `#4DA3DC`). Sources and generators in `design/icon/`.
- **Window:** transparent title bar, toolbar background hidden, no opaque title strip. The window itself is glass (`WindowGlass`, 2026-10-17): the desktop shows through, blurred, under a light ice tint. Screens don't paint their own backgrounds over it. Values still sit on opaque paper: the project `.env` is a paper sheet floating on the glass. The lock curtain stays opaque, so nothing shows through while it covers secrets. Reduce Transparency makes the glass solid (macOS does this).
- **Sidebar toggle:** our own button in the content's part of the toolbar (`.navigation`), like Dinky, with the built-in one removed (`.toolbar(removing: .sidebarToggle)`). The built-in toggle sits in the sidebar's part of the toolbar, which is too narrow for it mid-animation, so macOS flashed the overflow » next to the lock switch. View › Show/Hide Sidebar (⌃⌘S) still works.
- **Toolbar:** one control, the lock switch, pinned to the right end of the title bar as an `NSTitlebarAccessoryViewController` (`LockSwitchAccessory`), not a toolbar item, so it never slides into the overflow (») menu while the sidebar animates. It carries its own glass capsule. The switch is a small two-position switch (open lock | closed lock) whose knob sits on the current state. It's always there, on the lock screen too. Before anything is saved it sits on unlocked, and clicking it says "Slinky can lock once you've saved your first item."
- **Lock and unlock take over the whole window** (`LockCurtain`). Locking: ice spreads out from the switch with a bright rim until it covers everything, the lock in the middle closes, and only then does the vault lock, so nothing secret is drawn under the ice. Unlocking: the lock opens, then the ice opens from the middle like an iris. Locks from the screen locking, sleep or idle happen at once, with no animation. Reduce Motion skips it.
- **Layouts:** see `docs/slinky-layouts.html`. A = project `.env` view, B = Library shelf, C = Quick Access (default), E = Rising Shelf (challenger), D = agent receipts, F = menu bar stack, G = widget.
- **Hotkey:** ⌥⌘K for Quick Access (not ⌃⌥Space, not ⇧⌘Space).
- **Sidebar:** a standard macOS list, not tiles. Derek rejected the Reminders-style tiles (2026-10-16).
  - Search field at the top (searches names, never values). Our own `SidebarSearchField`, not `.searchable`: the built-in one moves into the toolbar when the sidebar hides and overflows (») during the animation. ⌘F focuses it, Esc clears it.
  - The top group (no heading, like Passwords and Notes; Derek dropped "Library" 2026-10-17): All Items, Keys & Tokens, Recovery, with SF Symbols and quiet counts. **Needs Attention** (orange) appears at the end only when something needs a person to act: codes running low, a project missing variables, a key expiring within 14 days. Each row says what to do and has a Show button.
  - Projects: a monogram per project; the count turns into an orange "2 missing" when `.env.example` lists variables Slinky doesn't have. Drop a .env file on a project to import it, or a folder to link it.
  - **One way to add each thing.** Items: Add Item (⌘N), which is the big button in every empty state, plus the File menu and the menu bar. There's no Add Item in the toolbar. Projects: a labeled "New Project" button in the sidebar footer (⇧⌘N), like Notes' "New Folder". No stray + buttons in headers or footers (Derek, 2026-10-16).
  - With no projects, the section shows a small card: a preview of a .env with hidden values, one line about what a project is, and a drop zone for a folder or .env file.
- **Naming:** Keys & Tokens, Recovery (Recovery Codes and Recovery Keys inside it), Projects, Add Item. No "Kept", "Tuck It Away" or "Secure Notes". Passwords and general notes belong in Apple Passwords and Notes, not Slinky (2026-10-16).
- **Empty states:** `VaultIdleAnimation`, Slinky's sibling to Dinky's IdleAnimation. A secret rises from the bottom edge, its characters turn into dots, it slides into the icon, the keyhole closes, the asterisk turns, and the keyhole returns with a draw-on checkmark. It plays four examples, one of everything Slinky saves (an API key, a project variable where only the value after `=` is hidden, recovery codes, a recovery key), and ends, like Dinky, on a resting collection: the same glass pills, level, in a loose hand-placed scatter around the icon (not a grid or rows). Hover replays it; Reduce Motion shows only the resting collection. The keyhole never rotates: only the asterisk turns (60°, so it lands identical). Below it: a title, one line, one button. Nothing more.
- **SF Symbol animations: only where something changes state.** `.replace` for swaps (Copy → checkmark, lock ↔ unlock), `.drawOn` for completion (the saved checkmark, a used code), `.pulse` while waiting for Touch ID. No bounces or wiggles on selection, detection, warnings or toasts: Derek found them too much (2026-10-16).
- **Filled SF Symbols everywhere** (Derek, 2026-10-17): `.symbolVariant(.fill)` is set once at each root (main window, Settings, Help, menu bar, Quick Access), so every symbol uses its filled variant where one exists. Write the plain name in code; the root fills it.
- **Monograms look like little Mac app icons:** a continuous squircle, a vibrant top-to-bottom gradient from a curated palette (glacier, teal, mint, indigo, violet, pink, coral, amber), a soft top sheen, a hairline rim and white initials. With no name yet, Slinky's asterisk on glacier. Examples in the app use "Slinky" as the project name.
- **Success is green.** Checkmarks that confirm something worked (saved, copied, stored) use system green. The ice-blue accent stays for actions and selection. Toasts have three looks: success (green checkmark), information (gray info icon) and removed (gray trash icon, with Undo). Toasts center over the content column, not the whole window.
- **Add Item** (`AddItemView.swift`, 2026-10-17): a floating glass panel (720 wide) over a soft dim, with a frosted layer behind it (`PanelBackdrop`), not a sheet. Never blur the window itself: it makes the layout jump under the toolbar. Raycast's one-field model, Apple Passwords' hide-by-default, and the empty-state pill motion.
  - Empty: one large field on paper ("Paste a key, recovery codes or .env lines", ⌘V keycap), plus "Or choose what you're adding": four equal tiles, each an icon, a name and one short description (two lines of text on purpose, never an accidental wrap), for typing something Slinky can't recognize.
  - On paste the value lands straight away: it becomes a slab on paper with the monogram, an editable name, and the value turning into dots left to right, settling into a short form (`sk_live_••••••••4f2a`). An eye shows it; an × clears it. `.env` pastes show `NAME=••••` rows; codes show a dotted grid; a wallet phrase turns the slab orange and saves nothing.
  - Under it: what Slinky thinks it is ("Looks like a GitHub token."), then the details as chips: where it goes (menu), expiry date, project and environment, website or username. Dashed chips are options you can add; tinted chips hold a choice.
  - Footer: "Encrypted on this Mac", Cancel, and "Save to Keys & Tokens ↵", so you always know where it's going.
- **New Project** (`NewProjectView.swift`, 2026-10-17): the same floating glass panel as Add Item. A big name field with a live monogram, then the project folder: a dashed drop zone ("Drop the project folder here", Choose Folder…) or, once chosen, its path with a git chip. Slinky reads the folder (`ProjectScan`, read-only) and lists what it found:
  - each `.env` file with a checkbox, its variable count and first few names (never values), and an environment chip guessed from the file name (`.env.local` → Local, `.env.staging` → Preview, `.env.production` → Production), which can be changed;
  - an orange "Not in .gitignore" chip on files git could commit, with one plain line of advice (Slinky never edits .gitignore itself);
  - `.env.example` (or .sample/.template/.dist) as the list of expected names, with "Still missing after import: …".
  - The button says what happens: "Create and Import 21 Variables ↵". Dropping a folder or .env file on the sidebar opens this panel with the folder already read.
- **Edit** (`EditItemView.swift`): the same floating panel, fields as label/control rows on paper (`FieldCard`). A value is never shown in full while editing: the current one is a peek, and "Replace…" opens a secure field for the new one. Recovery codes can be replaced with a new set (used marks reset). Remove/Delete sits bottom left, with a confirmation and Undo.
- **Settings** (`SettingsView.swift`): Dinky's Settings chrome. A `Window` scene with a unified title bar showing the pane's name, back and forward buttons, a hidden toolbar background, and a sidebar in sections (Settings: General, Security, Recovery Key; Slinky: About). Grouped forms, 760 × 560. About shows honest stats: secrets kept out of files, times copied, and "Seen by: You".
- **Help** (`HelpView.swift`): Help › Slinky Help, short plain sections on paper cards.
- **Duplicates** (2026-10-17): Add Item and Import compare the pasted value with what's saved, in memory while unlocked (`AppModel.places(of:)`), and say where it already is ("Already saved in Keys & Tokens, as GITHUB_TOKEN."). A warning, never a block. Nothing derived from values is stored for this.
- **Import** (`ImportView.swift`, `Importer` in the core): File › Import from 1Password or CSV… (⇧⌘I), and a quiet link on the All Items empty state. Reads `.1pux` (a small in-memory ZIP reader; nothing extracted to disk) or CSV. Keeps API credentials, concealed fields that are clearly service keys, backup codes and recovery keys found in notes. Skips logins, passwords and wallet phrases, and says how many it skipped. The panel lists names and peeks only, with items already in Slinky unchecked, and offers to move the export file to the Trash afterwards (on by default; export files aren't encrypted).
- **Needs Attention** also lists recovery keys with no copy outside Slinky, with Print… and "I Have a Copy" right in the row.
- **Working state:** the keyhole is absorbed into the asterisk, which spins (see `docs/plan.md`).

## Live documents
- Brief: https://claude.ai/artifact/McGgBjGnbNoYo5WwDqKURU (`docs/slinky-brief.html`)
- Layouts: https://claude.ai/artifact/8YhiTxEgrAT4oewnE1D37c (`docs/slinky-layouts.html`)
- Research: `docs/research-*.md`
