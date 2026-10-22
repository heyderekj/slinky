# Slinky

**Slinky keeps secrets out of files.** A small, native Mac app for the things you're told to "store somewhere safe": API keys and tokens, each project's `.env` variables, two-step backup codes and recovery keys.

The family: [Dinky](https://github.com/heyderekj/dinky) makes files smaller. [Binky](https://github.com/heyderekj/binky) sorts your files. Slinky keeps secrets out of files.

## What it does

- **Paste anything secret.** Press ⌘N and paste. Slinky turns the value into dots right away, recognizes common services (Stripe, OpenAI, Anthropic, GitHub, Supabase, Resend, AWS and more), and suggests where it belongs.
- **Projects for `.env` files.** Drop a project folder and Slinky reads its `.env` files, sorts them into Local, Preview and Production, checks they're in `.gitignore`, and uses `.env.example` to show what's missing.
- **Recovery codes that cross themselves off.** Copy a backup code and Slinky marks it used, and tells you when you're running low.
- **Quick Access, ⌥⌘K.** Find and copy anything from any app. Copies are marked private, so clipboard history apps skip them, and they clear themselves.
- **The `slinky` command.** `slinky run -- npm run dev` starts your app with a project's variables after Touch ID, with no `.env` on disk. `slinky xcconfig` for Xcode builds, `slinky env --export` and an optional zsh hook that loads a project's variables when you `cd` into it.
- **AI agents use secrets without seeing them.** Connect Claude Code, Cursor, Codex or Claude (MCP, names only). Agents run commands through `slinky run`, you approve each one with Touch ID, and live keys stay out. A missing key opens Slinky for you to paste, not the chat.
- **Health.** Finds exact copies of your saved values in your projects, their git history, AI tools' saved conversations and shell history (on your Mac, names and places only), with one-click fixes, a commit check, low codes, missing variables and keys about to expire.
- **Apple developer files.** App Store Connect `.p8` keys, certificates and service-account JSON kept in the vault; save a notarytool profile without the `.p8` lying around; hand a file to a command as a private temp file.
- **Make a new key, send it where it runs.** "Make New Key on GitHub…" opens the right page and replaces it everywhere it's used. Send a project's variables to Vercel, Netlify, Cloudflare or Fly through their own tools.
- **Activity.** What was copied or used, when and by whom. Names only.
- **No accidental doubles.** Paste something you've already saved and Slinky tells you where it is.
- **Import what you already have.** Bring keys over from another app: a `.1pux` export from 1Password, or a CSV from Apple Passwords, Bitwarden or a spreadsheet of keys. Slinky picks out keys, tokens, backup codes and recovery keys, and leaves passwords for Apple Passwords.
- **Locks itself.** Touch ID to open. Locks with your screen, on sleep, when you're away, and after 12 hours.
- **Shortcuts.** Add to Slinky, Copy from Slinky (Touch ID every time), Open Quick Access and Lock Slinky.

## Where your things live

In one encrypted file on your Mac. The key that opens it is protected by your Mac's Secure Enclave (Touch ID), with a printed Recovery Key as the backup. No account, no server, no sync. Time Machine backs the file up like any other, still encrypted.

Slinky goes online for a daily check with GitHub for a newer version (you can turn it off in Settings) and, only if you turn on Load icons from websites, to ask each saved website for its icon. When you choose Send to Host, that host's own command-line tool sends the values you picked to that service. Nothing about you or your vault is sent. Updates install in place, and only if they're signed by Slinky's developer.

Slinky doesn't store passwords (that's Apple Passwords) or crypto wallet recovery phrases.

## Install

**Requires a Mac with Apple silicon and macOS 15 (Sequoia) or later.** On macOS 26 Tahoe it uses Liquid Glass; on Sequoia, the standard frosted look.

Download the latest DMG from [Releases](https://github.com/heyderekj/slinky/releases/latest), drag Slinky to Applications and open it.

Slinky is signed but not yet notarized, so the first time macOS will say it can't check it. Open **System Settings › Privacy & Security**, scroll down, and click **Open Anyway** next to Slinky. You only do this once.

**Homebrew:**

```bash
brew tap heyderekj/slinky https://github.com/heyderekj/slinky
brew install --cask slinky
```

## Coming next

A Raycast extension, and sync between your Macs (encrypted before it leaves) once Slinky has a Developer ID.

## Build it yourself

```bash
xcodebuild -project Slinky.xcodeproj -scheme Slinky -configuration Debug -destination 'platform=macOS' -derivedDataPath build/dd build
cd SlinkyCore && swift test
```

Apple frameworks only, no third-party dependencies. See `CLAUDE.md` for the security rules and `docs/DESIGN.md` for design decisions.

## About

Made by [Derek Castelli](https://www.heyderekj.com) at Testament Made, LLC. Free and open source under the MIT License. Questions: derek@testamentmade.com.
