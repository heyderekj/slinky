# Slinky for Raycast — plan

Written 2026-10-17. Status: plan only. Depends on the `slinky` command and the app's socket broker (the agents milestone, v1.1).

## Why
Many of the people Slinky is for live in Raycast. ⌥⌘K Quick Access already covers "find and copy" inside Slinky, but Raycast users want it in the launcher they already have open: type "slinky stripe", press Return, done. It's also a natural place to add things ("Add Clipboard to Slinky") and to see what needs attention.

## The rules (same as everywhere else in Slinky)
1. **Values never pass through Raycast.** The extension only ever sees names, kinds, peeks (`sk_live_…4f2a`) and counts. When you copy, the Slinky app puts the value on the clipboard itself, the careful way (private, current device only, clears itself). Raycast's own process never holds the value.
2. **Raycast is a caller like any agent.** It goes through the `slinky` command and the app's broker, which checks the command is Slinky's own signed binary and shows who's asking (the process chain, e.g. "Raycast › slinky").
3. **Plain words.** Command names and messages follow `VOICE.md`. No clever labels.
4. **Nothing extra stored.** The extension keeps no cache of names on disk.

## Commands
| Command | What it does | Notes |
|---|---|---|
| **Search Slinky** | A list of everything by name: keys, project variables (with project and environment), recovery codes and recovery keys. Each row: monogram, name, where it lives, peek. | Return: Copy. ⌘Return: Copy as `KEY=value` (variables). ⌘O: Show in Slinky. For recovery codes, Return copies the next unused code and crosses it off. |
| **Add Clipboard to Slinky** | Opens Slinky's Add Item with whatever's on the clipboard, for you to check and save. | The app reads the clipboard itself (`slinky add --clipboard`), so the value doesn't travel through the extension. |
| **Lock Slinky** | Locks Slinky now. | No view, just a confirmation toast. |
| **Needs Attention** | Low codes, missing variables, keys about to expire, recovery keys without a printed copy. | Return: Show in Slinky. |
| Later: **Run with Slinky** | Pick a project and a command; runs it with that project's variables. | Only once `slinky run` exists and has been lived with. |

When Slinky is locked, every command shows one row: "Slinky is locked" with an Unlock action, which brings Slinky forward for Touch ID. When Slinky isn't installed, the extension shows "Slinky isn't installed" with a link to slinkyfiles.com.

## How it works
```
Raycast extension (TypeScript, @raycast/api)
   │  execFile, JSON on stdout
   ▼
slinky (the CLI inside Slinky.app, Contents/MacOS/slinky)
   │  Unix socket, newline-delimited JSON, peer-checked
   ▼
Slinky.app broker ──► checks the caller, asks if needed, does the copy itself, writes a receipt
```

### CLI contract the extension relies on
All commands support `--json`. None return a value.

| Command | Returns |
|---|---|
| `slinky status --json` | `{ "installed": true, "locked": false, "version": "1.1.0" }` |
| `slinky ls --json` | `[{ "id", "kind": "key" \| "variable" \| "codes" \| "recoveryKey", "name", "where", "peek", "isLive", "remaining"? }]` |
| `slinky copy <id> [--line]` | `{ "ok": true, "clearsIn": 60 }`. The app copies. `--line` copies `KEY=value`. |
| `slinky add --clipboard` | `{ "ok": true }`. Opens Add Item in the app, prefilled from the clipboard. |
| `slinky lock` | `{ "ok": true }` |
| `slinky attention --json` | `[{ "id", "title", "detail" }]` |

Errors are JSON too: `{ "error": "locked" | "notAllowed" | "notFound", "message": "Slinky is locked." }`.

### Who's allowed to copy
Anything on the Mac can run `slinky copy`, so copying can't be free for any caller. Options:

- **A. Touch ID on every copy from Raycast.** Safest, and tiring.
- **B. Allow Raycast once per unlock (recommended).** The first time Raycast asks after you unlock, Slinky shows a small card: "Raycast wants to copy from Slinky" with the process chain, and you confirm with Touch ID. Slinky then trusts that caller until it locks. The broker checks the caller is really Raycast by its code signature (identifier `com.raycast.macos` and Raycast's team ID), not just its name.
- Items set to "Never leaves" (the AI agents setting) can't be copied from Raycast at all; Slinky says so and offers Show in Slinky.

Every copy from Raycast gets a receipt in Slinky's history: what, when, which caller.

### Finding the CLI
Default path `/Applications/Slinky.app/Contents/MacOS/slinky`, then `~/Applications/…`, then whatever `slinky` is on the PATH (Homebrew symlink). An extension preference lets people point at a custom location.

## Raycast specifics
- Built with `@raycast/api` (React + TypeScript): `List` with sections (Keys & Tokens, Projects, Recovery), `ActionPanel`, `showToast`, `getPreferenceValues`, `open` for "Show in Slinky" (via a `slinky://` URL that only navigates, never copies).
- We never use Raycast's `Clipboard.copy`. The app does the copying, which keeps the value out of Raycast's process and its clipboard history.
- Source lives in this repo at `integrations/raycast/`. Publishing means a pull request to Raycast's extensions repository and their review. Their store needs a 512 × 512 icon, screenshots and a README, all in Slinky's plain voice.
- Store listing: **Slinky**. "Find, copy and add your API keys, .env variables and recovery codes, without the values ever passing through Raycast." Categories: Developer Tools, Security.

## Milestones
1. **CLI and broker** (agents milestone): `status`, `ls`, `copy`, `lock` with JSON output, the peer check, the per-unlock caller allowance, receipts.
2. **Extension v0.1:** Search Slinky and Lock Slinky, locked and not-installed states. Try it locally with `ray develop`.
3. **v0.2:** Add Clipboard to Slinky and Needs Attention. Screenshots and store README.
4. **Store submission.**
5. Later: Run with Slinky.

## Decisions for Derek
1. **Who's allowed to copy:** B (allow once per unlock, with Touch ID) or A (Touch ID every time)?
2. **Recovery codes in Raycast:** show them (Return copies the next code), or keep recovery things Slinky-only?
3. **Store author:** publish under your Raycast handle (heyderekj?) with "Testament Made, LLC" in the README?
