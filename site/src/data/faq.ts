// The FAQ, shared by the page and /ask.json (what Spotlight's answers are grounded in).
export const faq: [string, string][] = [
  ['Is Slinky free?', 'Yes. Slinky is free and open source under the MIT License, made by Testament Made, LLC, the same people behind Dinky and Binky.'],
  ['Where are my things stored?', 'In one encrypted file on your Mac. The key that opens it is protected by your Mac’s Secure Enclave and opened with Touch ID. A printed Recovery Key is the backup.'],
  ['Is there an account or sync?', 'No account, no server and no sync. Slinky goes online for a daily check with GitHub for a newer version, which you can turn off, and, only if you turn it on, to ask each saved website for its icon. Time Machine backs up the encrypted file like any other.'],
  ['What if I lose my Mac?', 'Restore your backup on a new Mac and open Slinky with your Recovery Key. Slinky then sets up Touch ID on that Mac.'],
  ['Why does macOS say it can’t check Slinky?', 'Slinky is signed but not notarized yet. The first time, open System Settings › Privacy & Security and click Open Anyway. You only do this once; updates install without asking again.'],
  ['Should I keep passwords in Slinky?', 'No. Website passwords belong in Apple Passwords. Slinky is for the other things: API keys, tokens, .env variables, backup codes and recovery keys.'],
  ['Does Slinky change my project files?', 'No. It reads your .env files and .gitignore to set things up. It only writes a file when you choose Save .env.example, which has names and no values.'],
  ['What about clipboard history apps?', 'Everything Slinky copies is marked private, so Raycast, Paste, Maccy and others skip it, and the clipboard clears itself after 60 seconds.'],
  ['Can I bring my keys from another app?', 'Yes. Import a 1Password export or a CSV from Apple Passwords, Bitwarden or a spreadsheet. Slinky picks out keys, tokens and codes, and leaves passwords behind.'],
  ['Will it work with AI coding tools?', 'That’s next. Slinky 1.1 adds a slinky command and an MCP connection, so tools like Claude Code can run your app with the real keys while only ever seeing dots.'],
];

/** A stable anchor for each question, e.g. "Is Slinky free?" → "faq-is-slinky-free". */
export const faqId = (q: string) => 'faq-' + q.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
