---
layout: ../../layouts/Guide.astro
title: Where to keep API keys on a Mac
seo: Where to keep API keys on a Mac · Slinky
description: API keys don’t belong in notes, chats or project folders. Here’s where to keep them on a Mac, what to avoid, and how Slinky keeps them encrypted and opens with Touch ID.
lede: An API key is a password for software. It deserves the same care as your passwords, but most of them end up in a notes app, a chat, or a .env file in a project folder.
faq:
  - ["Can I keep API keys in Apple Passwords?", "You can paste one into a password’s notes, but Apple Passwords is made for website sign-ins and passkeys. It has no way to group keys by project or environment, and nothing to hand them to a command. It’s the right place for your passwords, including your Slinky Recovery Key."]
  - ["Is Keychain Access a good place for API keys?", "It’s encrypted and built in, and the security command can read items back. But it was never made for keys: no projects, no environments, and reading a value from a script prints it into your terminal and shell history."]
  - ["Does Slinky send my keys anywhere?", "No. Your keys stay in one encrypted file on your Mac. Slinky goes online only to check GitHub for updates (you can turn that off) and, if you turn it on, to load website icons. If you turn on sync, it writes an encrypted copy to a folder you choose, and your own sync service moves it."]
---

## Where keys usually end up

Keys tend to land wherever they were first pasted:

- **A notes app or a document.** Easy to find, and easy to sync, share or screenshot by accident. Nothing marks the note as secret.
- **A chat or an email to yourself.** Now the key lives on someone else’s server, in search results, and in every device that’s signed in.
- **A `.env` file in the project folder.** This is how most frameworks expect it, and it works. But the file is plain text, it gets copied with the folder, and one mistake in `.gitignore` puts it in your repository. See [Keep .env files out of git](/guides/keep-env-files-out-of-git/).
- **Your shell history.** Running `export STRIPE_SECRET_KEY=sk_live_…` once leaves the key in `~/.zsh_history`.
- **An AI tool’s conversation.** Paste a key into a chat to debug something, and it stays in that tool’s saved history.

None of these are encrypted just for the key, and none of them tell you where a key is used.

## What a good place looks like

Whatever you use, look for these:

1. **Encrypted at rest**, and locked when you’re away.
2. **Organised by project and environment**, so `STRIPE_SECRET_KEY` for Local and for Production don’t get mixed up.
3. **A way to use a key without copying it into a file**, such as a command that starts your app with the variables it needs.
4. **Careful copying.** When you do copy a key, clipboard history apps shouldn’t keep it, and the clipboard should clear itself.
5. **A backup you control**, so a lost Mac isn’t a lost set of keys.

A team that shares keys across many machines and servers usually wants a hosted secret manager such as Doppler, Infisical or HashiCorp Vault. One person, or a small team where each person has their own keys, often doesn’t need a server at all. Our [comparisons](/compare/) go through the trade-offs.

## How Slinky does it

[Slinky](/) is a free, open-source Mac app made for exactly these things: API keys and tokens, each project’s `.env` variables, and two-factor backup codes.

- **Paste it once.** Press ⌘N and paste. The value turns into dots straight away, and Slinky says what it looks like (“Looks like a Stripe live key.”) and suggests where it goes.
- **Encrypted on your Mac.** Everything is in one encrypted file. Your Mac’s Secure Enclave protects the key that opens it, and Touch ID unlocks it. A printed Recovery Key is the backup. There’s no account and no server.
- **Locks itself.** When your screen locks, when your Mac sleeps, after 10 minutes away and after 12 hours.
- **Projects and environments.** Drop a project folder on Slinky and it reads the `.env` files, showing Local, Preview and Production side by side.
- **Use keys without a file.** `slinky run -- npm run dev` starts your app with the project’s variables after Touch ID, with no `.env` on disk.
- **Careful copying.** Press ⌥⌘K in any app to find a key and copy it. Copies are marked private, so clipboard history apps skip them, and the clipboard clears after 60 seconds.
- **Finds the copies you forgot.** Health looks for your saved values in linked projects, their git history, AI tools’ saved conversations and your shell history, on your Mac, and tells you the names and places.

Already have keys in another app? Slinky imports a 1Password export, or a CSV from Apple Passwords, Bitwarden, LastPass or KeePass, picks out the keys and tokens, and leaves your passwords behind.

> Slinky keeps keys out of files and out of sight. It isn’t a sandbox: a program you run with a key can still use that key.
