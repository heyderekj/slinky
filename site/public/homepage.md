# Slinky keeps secrets out of files.

A free Mac app for API keys, .env variables and recovery codes. Encrypted on your Mac, opened with Touch ID.

[Download for Mac](https://github.com/heyderekj/slinky/releases/latest) · [GitHub](https://github.com/heyderekj/slinky) · macOS 26 Tahoe or later · Apple silicon

## Everything you're told to "store somewhere safe"

API keys, each project's .env, backup codes and recovery keys. Paste it, and Slinky knows where it goes.

- **Paste anything secret.** Press ⌘N and paste. The value turns into dots right away, Slinky says what it looks like, and suggests where it belongs.
- **Your app's secrets, out of its files.** Drop a project folder. Slinky reads its .env files, sorts them into Local, Preview and Production, and shows what .env.example says is missing.
- **Backup codes, ready when you're locked out.** Copy a code and Slinky crosses it off. It tells you when you're running low.
- **⌥⌘K, from anywhere.** Find a key by name and press Return. Copies are private and clear themselves after a minute.
- **Locks itself.** Touch ID to open. Locks with your screen, on sleep, when you're away, and after 12 hours.
- **AI agents use your keys without seeing them.** Claude Code, Cursor and Codex run your app through `slinky run`. You approve each command with Touch ID; agents only ever see names.

## Also in Slinky

The slinky command · Health (finds keys in project files, git history, AI conversations and shell history) · Apple developer files and notarytool profiles · Make a new key, send it to your host · Activity · Import from 1Password or CSV · Shortcuts actions · Settings for locking and the clipboard · Updates that install in place · Native Swift, a 5 MB download, no dependencies.

## Your things, in plain English

- One encrypted file on your Mac, opened by the Secure Enclave with Touch ID or your printed Recovery Key.
- No account, no server, no sync. Network calls: a daily update check with GitHub, which you can turn off, and, only if you turn it on, a request to each saved website for its icon. When you choose Send to Host, the values you pick go to that host through its own tool.

## Coming next

A Raycast extension, and sync between Macs once Slinky has a Developer ID.

Made by Testament Made, LLC · derek@testamentmade.com · MIT License
