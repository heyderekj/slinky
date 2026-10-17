# Slinky

**Slinky keeps secrets out of files.** A small, native Mac app for the things you're told to "store somewhere safe": API keys and tokens, each project's `.env` variables, two-step backup codes and recovery keys.

The family: [Dinky](https://github.com/heyderekj/dinky) makes files smaller. [Binky](https://github.com/heyderekj/binky) sorts your files. Slinky keeps secrets out of files.

## What it does

- **Paste anything secret.** Press ⌘N and paste. Slinky turns the value into dots right away, recognizes common services (Stripe, OpenAI, Anthropic, GitHub, Supabase, Resend, AWS and more), and suggests where it belongs.
- **Projects for `.env` files.** Drop a project folder and Slinky reads its `.env` files, sorts them into Local, Preview and Production, checks they're in `.gitignore`, and uses `.env.example` to show what's missing.
- **Recovery codes that cross themselves off.** Copy a backup code and Slinky marks it used, and tells you when you're running low.
- **Quick Access, ⌥⌘K.** Find and copy anything from any app. Copies are marked private, so clipboard history apps skip them, and they clear themselves.
- **Needs Attention.** Low codes, missing variables, keys about to expire and recovery keys with no printed copy, in one place.
- **No accidental doubles.** Paste something you've already saved and Slinky tells you where it is.
- **Import what you already have.** Bring keys over from another app: a `.1pux` export from 1Password, or a CSV from Apple Passwords, Bitwarden or a spreadsheet of keys. Slinky picks out keys, tokens, backup codes and recovery keys, and leaves passwords for Apple Passwords.
- **Locks itself.** Touch ID to open. Locks with your screen, on sleep, when you're away, and after 12 hours.
- **Shortcuts.** Add to Slinky, Copy from Slinky (Touch ID every time), Open Quick Access and Lock Slinky.

## Where your things live

In one encrypted file on your Mac. The key that opens it is protected by your Mac's Secure Enclave (Touch ID), with a printed Recovery Key as the backup. No account, no server, no sync. Time Machine backs the file up like any other, still encrypted.

The only time Slinky goes online is a daily check with GitHub for a newer version (you can turn it off in Settings). Updates install in place, and only if they're signed by Slinky's developer.

Slinky doesn't store passwords (that's Apple Passwords) or crypto wallet recovery phrases.

## Install

**Requires a Mac with Apple silicon and macOS 26 (Tahoe) or later.**

Download the latest DMG from [Releases](https://github.com/heyderekj/slinky/releases/latest), drag Slinky to Applications and open it.

Slinky is signed but not yet notarized, so the first time macOS will say it can't check it. Open **System Settings › Privacy & Security**, scroll down, and click **Open Anyway** next to Slinky. You only do this once.

**Homebrew:**

```bash
brew tap heyderekj/slinky https://github.com/heyderekj/slinky
brew install --cask slinky
```

## Coming next

AI agents that use your secrets without seeing them: a `slinky` command that runs your app with the real keys while the agent only ever sees dots, a request card when something sensitive is needed, and a record of what each agent used. Then a Raycast extension.

## Build it yourself

```bash
xcodebuild -project Slinky.xcodeproj -scheme Slinky -configuration Debug -destination 'platform=macOS' -derivedDataPath build/dd build
cd SlinkyCore && swift test
```

Apple frameworks only, no third-party dependencies. See `CLAUDE.md` for the security rules and `docs/DESIGN.md` for design decisions.

## About

Made by [Derek Castelli](https://www.heyderekj.com) at Testament Made, LLC. Free and open source under the MIT License. Questions: help@slinkyfiles.com.
