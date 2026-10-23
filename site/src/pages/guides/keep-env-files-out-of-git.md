---
layout: ../../layouts/Guide.astro
title: Keep .env files out of git
seo: How to keep .env files out of git · Slinky
description: How to stop .env files and API keys from being committed. Check .gitignore, commit a names-only .env.example, block commits with secrets, and what to do if a key already leaked.
lede: A .env file is the usual home for a project’s keys, and it’s one forgotten line in .gitignore away from your repository. A few habits keep it out.
faq:
  - ["Is it enough to add .env to .gitignore?", "It’s the first step, and it only stops files git isn’t already tracking. If .env was committed before, git keeps tracking it until you remove it from the index, and the old commits still contain it."]
  - ["I already pushed a key. Is deleting the file enough?", "No. The key is still in your git history, and anyone who cloned or forked the repository has it. Make a new key on the service first and turn the old one off. Cleaning history afterwards is good housekeeping, not a fix."]
  - ["Does Slinky change my project files?", "Only when you ask. It reads .env files and .gitignore to show what it found. It writes a file only when you choose Save .env.example, Move into Slinky, or Stop Commits with Secrets."]
---

## Why it keeps happening

`.env` files are plain text in the project folder, next to everything you do want to commit. They leak in a few ordinary ways:

- The project started without a `.gitignore`, or with one that covers `.env` but not `.env.local` or `.env.production`.
- The file was committed once, before the ignore rule, so git still tracks it.
- `git add .` or an AI coding tool staged everything in the folder.
- The folder was zipped, shared or copied somewhere public.

GitGuardian counted 28.65 million new secrets in public GitHub commits in 2025 ([State of Secrets Sprawl 2026](https://blog.gitguardian.com/the-state-of-secrets-sprawl-2026/)).

## Check .gitignore

Make sure every variant is covered, and that `.env.example` is still allowed:

```bash
# .gitignore
.env
.env.*
!.env.example
```

Then ask git whether it’s already tracking one:

```bash
git ls-files | grep -E '(^|/)\.env'
```

If that prints anything other than `.env.example`, stop tracking it (the file stays on disk):

```bash
git rm --cached .env
```

## Commit names, not values

A `.env.example` with the names and no values tells the next person (or the next machine) which variables the project needs:

```bash
STRIPE_SECRET_KEY=
RESEND_API_KEY=
DATABASE_URL=
```

## Block commits with a key in them

A pre-commit hook can check staged changes before each commit. General-purpose scanners such as gitleaks look for things shaped like keys. Slinky’s check looks for exact copies of keys you’ve saved, so it doesn’t need to guess.

## If a key was already pushed

1. **Make a new key** on the service and turn the old one off. This is the step that matters.
2. Update every place that used the old key.
3. Then, if you like, clean the history with a tool such as `git filter-repo`. Forks and clones keep the old copy either way.

## How Slinky does it

[Slinky](/) gives each project’s variables a home outside the folder:

- **Drop the project folder on Slinky.** It reads the `.env` files (apps inside the folder too), shows Local, Preview and Production side by side, and warns about any file git could commit.
- **Move into Slinky.** One click saves the variables, writes a `.env.example` with names only, and puts the `.env` in the Trash.
- **Run without a file.** `slinky run -- npm run dev` starts your app with the variables after Touch ID. `slinky hook zsh` can load them when you `cd` into the project and unload them when you leave.
- **Stop Commits with Secrets.** In a project’s Import menu, or `slinky guard install` from Terminal, adds a git hook that checks each commit for your saved values.
- **Make New Key.** Slinky opens the service’s page for making keys, and when you paste the new one, every project using the old key gets it.
