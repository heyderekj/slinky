# Slinky keeps secrets out of files.

A free Mac app for API keys, .env variables and recovery codes. Encrypted on your Mac, opened with Touch ID.

[Download for Mac](https://github.com/heyderekj/slinky/releases/latest) · [GitHub](https://github.com/heyderekj/slinky) · macOS 15 Sequoia or later · Apple silicon

## Everything you're told to "store somewhere safe"

API keys, each project's .env, backup codes and recovery keys. Paste it, and Slinky knows where it goes.

- **Paste anything secret.** Press ⌘N and paste. The value turns into dots right away, Slinky says what it looks like, and suggests where it belongs.
- **Your app's secrets, out of its files.** Drop a project folder. Slinky reads its .env files (apps inside it too) and shows what's new, changed or the same in Local, Preview and Production. Only what you check is saved, and Undo takes it back. It shows what .env.example says is missing.
- **Backup codes, ready when you're locked out.** Copy a code and Slinky crosses it off. It tells you when you're running low.
- **⌥⌘K, from anywhere.** Find a key by name and press Return. Copies are private and clear themselves after a minute.
- **Locks itself.** Touch ID to open. Locks with your screen, on sleep, when you're away, and after 12 hours, or from Lock Slinky in Control Center (macOS 26 and later).
- **Your vault on each of your Macs.** Optional sync through a folder you choose, like one in iCloud Drive: an encrypted copy that opens only with your Recovery Key or on a Mac you've set up. Slinky itself sends nothing.
- **Share keys with your team. No server in between.** Pick people and Slinky makes a .slinkyshare file only their Macs can open; send it any way you like. Compare codes once in People (⌘8). Shared projects keep one signed, encrypted .slinkyproject file in a folder your team already syncs. Removing someone makes a new key, and Slinky lists the keys to replace, since they keep what they saw.
- **AI agents use your keys without seeing them.** Claude Code, Cursor and Codex run your app through `slinky run`. You approve each command with Touch ID; agents only ever see names.
- **A post-quantum lock.** On macOS 26 and later, the vault key and sharing use P-256 plus ML-KEM-768, with ML-DSA-65 signatures. An older vault moves over the next time you unlock it.
- **Ready for macOS 27.** Slinky's menu bar menu works from the keyboard like the menus beside it (Control-F8, then the arrow keys). Lock Slinky from Control Center or the menu bar (macOS 26 and later). In Shortcuts, Copy from Slinky and Add to Slinky run only in Slinky itself.

## Also in Slinky

The slinky command · Health (finds keys in project files, git history, AI conversations and shell history) · Apple developer files and notarytool profiles · Make a new key, send it to your host · Activity · Import from 1Password, Apple Passwords, Bitwarden, LastPass, KeePass or CSV · ⌘1–⌘8, select several, Undo · Shortcuts actions · Settings for locking and the clipboard · Updates that install in place · Native Swift, a 5 MB download, no dependencies.

## Your things, in plain English

- One encrypted file on your Mac, opened by the Secure Enclave with Touch ID or your printed Recovery Key. On macOS 26 and later, the key that opens it is locked with both a classic and a post-quantum key (P-256 and ML-KEM-768).
- No account and no server. Optional sync keeps an encrypted copy in a folder you choose, moved by your own sync service. Network calls: a daily update check with GitHub, which you can turn off, and, only if you turn it on, a request to each saved website for its icon. When you choose Send to Host, the values you pick go to that host through its own tool. When you share, Slinky makes a signed, encrypted file only the people you pick can open; you send it, or your team's own sync service moves it.

## Coming next

A Raycast extension, and sync through your own Postgres or S3-compatible storage (still encrypted before it leaves the Mac).

Made by Testament Made, LLC · derek@testamentmade.com · MIT License
