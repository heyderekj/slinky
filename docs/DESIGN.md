# Slinky — design principles and references

Read this before any design work. Every visual decision should trace back to something here. If it doesn't, decide on purpose and add it.

## Principles
1. **Intentional and tasteful over busy.** Each screen has one job and one primary action. When in doubt, remove.
2. **Native Tahoe first.** Use system components (`NavigationSplitView`, inspector, toolbar, sheets, glass buttons) before inventing. Custom only where Slinky has something to say: the `.env` view, recovery-code chips, Quick Access, approval cards.
3. **Glass on chrome, paper under values.** Liquid Glass belongs to sidebars, toolbars, floating panels, menu bar cards and toasts. Secret values always sit on opaque cool paper (`Color.paper`), in monospace, at 4.5:1 contrast or better. Never glass on glass.
4. **Ice, not blue.** The brand is clear, glassy and white, with glacier/ice blue. Accent `#4a7aa3` light / `#a9c7dc` dark, used once per view on the primary action. No saturated blue in UI chrome.
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
- **Window:** transparent title bar, toolbar background hidden, ice as the window background. No opaque title strip.
- **Layouts:** see `docs/slinky-layouts.html`. A = project `.env` view, B = Library shelf, C = Quick Access (default), E = Rising Shelf (challenger), D = agent receipts, F = menu bar stack, G = widget.
- **Hotkey:** ⌥⌘K for Quick Access (not ⌃⌥Space, not ⇧⌘Space).
- **Sidebar:** a standard macOS list, not tiles. Library (All Items, Keys & Tokens, Recovery Codes, Secure Notes) with SF Symbols and quiet counts, then Projects. A small + menu at the bottom. Derek rejected the Reminders-style tiles (2026-10-16).
- **Naming:** Keys & Tokens, Recovery Codes, Secure Notes, Projects, Add Item. No "Kept" or "Tuck It Away".
- **Empty states:** `VaultIdleAnimation`, Slinky's sibling to Dinky's IdleAnimation. A secret rises from the bottom edge, its characters turn into dots, it slides into the icon, the keyhole closes, the asterisk turns, and the keyhole returns with a draw-on checkmark. It ends, like Dinky, on a resting collection of examples fanned under the icon. Hover replays it; Reduce Motion shows only the resting collection. The keyhole never rotates: only the asterisk turns (60°, so it lands identical). Below it: a title, one line, one button. Nothing more.
- **SF Symbol animations, used for meaning, not decoration:** `.replace` for state swaps (Copy → checkmark), `.drawOn` for completion (used codes, saved), `.bounce` for acknowledgement (selection, detection, toasts), `.pulse` while waiting (Touch ID), `.wiggle` for gentle warnings (low codes). One effect per moment.
- **Success is green.** Checkmarks that confirm something worked (saved, copied, stored) use system green. The ice-blue accent stays for actions and selection.
- **Working state:** the keyhole is absorbed into the asterisk, which spins (see `docs/plan.md`).

## Live documents
- Brief: https://claude.ai/artifact/McGgBjGnbNoYo5WwDqKURU (`docs/slinky-brief.html`)
- Layouts: https://claude.ai/artifact/8YhiTxEgrAT4oewnE1D37c (`docs/slinky-layouts.html`)
- Research: `docs/research-*.md`
