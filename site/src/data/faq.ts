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
  ['Will it work with AI coding tools?', 'Yes. Connect Claude Code, Cursor, Codex or Claude in Settings. Agents see names, never values: they run your app through slinky run, you approve each command with Touch ID, and live keys stay out. Holding back keys this way keeps them out of the model, not out of a determined program; Slinky isn’t a sandbox.'],
  ['Does Slinky read my files?', 'Only to help, and only on your Mac. Health looks for exact copies of your saved values in linked projects and their git history, AI tools’ saved conversations and your shell history, and reports names and places. Nothing is sent anywhere.'],
  ['Can it send my variables to Vercel or Cloudflare?', 'Yes, when you choose Send to Host in a project. Slinky uses the host’s own command-line tool, signed in as you: Vercel, Netlify, Cloudflare Workers or Pages, or Fly.io. You see the names first, and Touch ID confirms it.'],
  ['Does it help with App Store Connect and notarization?', 'Yes. Keep your App Store Connect .p8 key in Slinky, add its Issuer ID, and save a notarytool profile from it, so the key isn’t lying in a folder. App-specific passwords are recognised when you paste them.'],
];

/** A stable anchor for each question, e.g. "Is Slinky free?" → "faq-is-slinky-free". */
export const faqId = (q: string) => 'faq-' + q.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
