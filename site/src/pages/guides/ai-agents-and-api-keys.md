---
layout: ../../layouts/Guide.astro
title: Let AI coding tools use your API keys without seeing them
seo: Claude Code, Cursor and your API keys · Slinky
description: AI coding tools read .env files and paste keys into chats. Here’s how to let Claude Code, Cursor and Codex run your app with its keys while the keys stay out of the conversation.
lede: An AI coding tool that can read your project can read its .env file, and anything it reads can end up in a conversation, a log or a commit. You can give it the names and keep the values.
faq:
  - ["Does this make running an agent completely safe?", "No. Slinky keeps values out of the model’s context and out of files. A command you approve still runs with the keys it was given, and a determined program could misuse them. Slinky isn’t a sandbox."]
  - ["Which tools work with Slinky?", "Claude Code, Cursor, Codex and Claude. Connect them in Settings › Command Line & Agents. Any tool that can run a terminal command can use slinky run."]
  - ["What if the agent needs a key I haven’t saved?", "It asks Slinky, and Slinky opens Add Item with the name filled in. You paste the key there, not in the chat."]
---

## Where keys leak with agents

- **Reading files.** An agent looking around your project opens `.env` like any other file, and the values go into its context.
- **Pasting into the chat.** “Here’s my key, can you fix the auth error?” puts it in the conversation history.
- **Printing it.** `echo $STRIPE_SECRET_KEY` or `printenv` to debug, and the value is in the transcript.
- **Committing it.** An agent that stages everything can commit a `.env` or a hard-coded key. GitGuardian found commits made with Claude Code leaked secrets at about twice the usual rate ([State of Secrets Sprawl 2026](https://blog.gitguardian.com/the-state-of-secrets-sprawl-2026/)).

## The general idea

Give the agent names, not values. It can know that `STRIPE_SECRET_KEY` exists and is needed, and start your app with it, without ever reading it:

1. Keep values out of the project folder, so there’s no `.env` to read.
2. Let the agent run commands through a tool that adds the variables to that one process.
3. Approve those commands yourself, and keep live keys out of reach.

Password managers and hosted secret managers have CLIs that do part of this (`op run`, `doppler run`, `infisical run`). What changes between them is where the values live and who approves each use.

## How Slinky does it

- **Connect in Settings.** Claude Code, Cursor, Codex or Claude connect to Slinky’s MCP server. Agents can list names, check which variables a project still needs, and ask for a key. No tool returns a value.
- **slinky run, with Touch ID.** To start your app, an agent runs `slinky run -- npm run dev`. You see the command and approve it with Touch ID. An agent’s approval is never reused.
- **Held back from agents:** live keys, anything you mark never for agents, shells, inline code, `env` and `printenv`, tools that send things off your Mac like `curl` and `ssh`, `git push` and publishing.
- **Missing keys go to Add Item**, not the chat.
- **Activity** shows what was used, when and by whom. Names only.
- **Health** checks Claude Code, Codex and Cursor’s saved conversations for copies of your saved values, on your Mac, and tells you where they are.

> This keeps keys out of the model and out of files. It doesn’t stop a program you approved from using the key it was given.
