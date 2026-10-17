# Slinky: personal vs. commercial use, personas and business model

*Research as of 2026-09-24. Sources are linked inline.*

## Executive summary

- **Leaks are growing, and AI speeds them up.**
  - GitGuardian counted 28.65M new hardcoded secrets on public GitHub in 2025, up 34%.
  - AI-service key leaks rose 81%.
  - Commits made with Claude Code leaked at 3.2%, against a 1.5% baseline.
  - 24,008 secrets turned up in MCP config files ([GitGuardian 2026](https://blog.gitguardian.com/the-state-of-secrets-sprawl-2026/)).
- **Most new builders are not developers.**
  - Lovable: about 8M users and about $500M ARR ([Wikipedia](https://en.wikipedia.org/wiki/Lovable_(company))).
  - Replit: 50M+ users. Bolt: 5M registered users in May 2025 ([Panto](https://www.getpanto.ai/blog/bolt-new-statistics)).
  - Hostinger says 63% of AI app-builder users have no coding background. That is its own internal data, so treat it as directional ([Hostinger](https://www.hostinger.com/blog/ai-app-builder-statistics/)).
- **The harm is real money and real data.**
  - One solo developer got an $82K Gemini bill in 48 hours from a stolen key ([The Register](https://www.theregister.com/security/2026/03/03/dev-stunned-by-82k-gemini-api-key-bill-after-theft/4925029)).
  - Moltbook put a Supabase key in its frontend and leaked 1.5M API tokens ([Wiz](https://www.wiz.io/blog/exposed-moltbook-database-reveals-millions-of-api-keys)).
  - CVE-2025-48757 exposed 170 of 1,645 scanned Lovable apps ([Superblocks](https://www.superblocks.com/blog/lovable-vulnerabilities)).
- **Agents read `.env` files.** Researchers documented Claude Code loading `.env` silently and ignoring instructions not to ([Knostic](https://www.knostic.ai/blog/claude-cursor-env-file-secret-leakage), [Eve](https://eve.gd/2026/04/19/claude-code-can-consume-transmit-and-compromise-your-env-files-even-if-you-tell-it-not-to/)).
- **A free local vault with MCP is already table stakes.**
  - NoxKey is free and AGPL, with Touch ID, MCP and no network access ([noxkey.ai](https://noxkey.ai/)).
  - PassStore is MIT ([GitHub](https://github.com/ilmakio/PassStore)).
  - SecretKit is free with tips and has end-to-end encrypted iCloud sync ([App Store](https://apps.apple.com/us/app/secretkit-api-key-manager/id6758926821?mt=12)).
  - 1Password has Environments ([1Password](https://1password.com/blog/1password-environments-env-files-public-beta)) and, since July 2026, "1Password for Claude" ([1Password](https://1password.com/press/2026/july/1password-for-claude)).
  - Slinky wins on craft, voice, plain-language guidance and **freelancer workflows**.
- **Team secret managers are free for 2–3 people** (Doppler for 3 users, Bitwarden Secrets Manager for 2), so sharing with a cofounder can't carry a subscription.
- **Recommendation:** an MIT core that stays free, plus Slinky Pro at about $15 one-time with $5/yr for updates, matching Binky. Include Slinky in a family bundle. Anything that keeps you safe, including backup and export, stays free.

## 1. Who builds software now, and how secrets leak

| Signal | Data |
|---|---|
| Developer AI use | 84% use or plan to use AI. 46% distrust its accuracy. About 72% say vibe coding isn't part of their professional work ([Stack Overflow 2025](https://survey.stackoverflow.co/2025/ai)) |
| Solo founders | 36% of startups founded on Carta in 2025 had a solo founder, up from 31% ([Carta](https://carta.com/data/solo-founders-report/)) |
| AI-service leaks | 1.27M leaked. 8 of the 10 fastest-growing detector types are AI services. Internal repos are 6× likelier to contain secrets. 28% of incidents happen in Slack, Jira or Confluence ([GitGuardian](https://blog.gitguardian.com/the-state-of-secrets-sprawl-2026/)) |
| Nothing gets fixed | 64% of secrets valid in 2022 were still exploitable in January 2026 |
| Vibe-coded apps | Escape.tech found 400+ exposed secrets across 5,600 apps. Wiz found risks in 20% of vibe-coded apps ([Wiz](https://www.wiz.io/blog/common-security-risks-in-vibe-coded-apps)) |
| Public keys that became secret | About 3,000 public Google Maps keys quietly gained Gemini access ([Truffle Security](https://trufflesecurity.com/blog/google-api-keys-werent-secrets-but-then-gemini-changed-the-rules)) |

**Common failure patterns:**
1. Keys shipped in frontend code. EnrichLead was shut down after this ([Vibe Graveyard](https://vibegraveyard.ai/story/enrichlead-vibe-coded-saas-shutdown/)).
2. The wrong key type. Supabase `service_role` / `sb_secret_` keys bypass Row Level Security ([Supabase](https://supabase.com/docs/guides/getting-started/api-keys)).
3. Keys pasted into chats and DMs.
4. Plaintext tokens in MCP configs.
5. Agents that read `.env` files.
6. Slow or no rotation.

GitHub forwards leaked Anthropic keys for automatic revocation, but only in public repos ([GitHub](https://github.blog/changelog/2024-08-20-anthropic-is-now-a-github-secret-scanning-partner/)).

## 2. Personas

**A. Weekend builder (a non-developer on Lovable, Bolt or Cursor)**
- *Pains:*
  - Can't tell a publishable key from a secret one.
  - Pastes keys into the chat.
  - Is afraid of a surprise bill.
- *Features that matter:*
  - Plain labels for each key: "safe in a browser" / "server only".
  - Presets for common services.
  - A "what is this key?" check on paste.
  - Clipboard auto-clear.
  - A one-screen "I leaked a key" guide for each provider.

**B. Tinkerer (automations, home lab, MCP servers, bring-your-own-key AI apps)**
- *Pains:* Tokens in `claude_desktop_config.json`, `.mcp.json`, dotfiles and cron. Claude Code supports `${VAR}` expansion, but the values still have to live somewhere ([docs](https://code.claude.com/docs/en/mcp)).
- *Features that matter:*
  - `slinky run --`.
  - An MCP-config helper that swaps hardcoded tokens for Slinky references.
  - A scan of existing config files for plaintext keys.
  - Per-project `.env` injection.

**C. Freelancer or small agency (Derek's own world)**
- *Pains:*
  - Client keys scattered across Notion, Slack and email.
  - No clean handoff at the end of a project.
  - Offboarding subcontractors.
  - Keeping clients separate.
- The standard guidance: transfer ownership to the client, then revoke your own access, and never paste credentials into handoff docs ([DEV](https://dev.to/instarenewal/digital-housekeeping-revoking-ssh-keys-and-admin-accounts-after-a-client-project-ends-19l1)).
- *Features that matter:*
  - Per-client workspaces.
  - A handoff package: an encrypted bundle plus a checklist of what exists, where it's used, and what to rotate after you leave.
  - "Forget this client", which deletes the secrets and records the date.
  - Per-client separation of what agents can see.

**D. Solo SaaS founder**
- *Pains:*
  - Mixing up Stripe live and test keys.
  - Rotation.
  - Incident response after a leak.
  - The first B2B security questionnaire. SOC 2 guidance asks for secrets kept in a manager, rotation after any exposure, and access reviews ([Promise Legal](https://promise.legal/guides/soc2-roadmap), [Rippling](https://www.rippling.com/blog/soc-2-for-startups)).
- *Features that matter:*
  - Separate environments.
  - An extra Touch ID prompt for live keys.
  - Rotation reminders based on each key's age.
  - An exportable local access log.
  - A "where is this key used" list.

**E. Two-person team (cofounder or trusted contractor)**
- *Pains:* Sharing one key means another account and another cloud.
- *Features that matter:* Share with one person, as an encrypted file or AirDrop with an expiry, then a nudge to rotate when access ends.

## 3. Personal vs. commercial feature split

**Free forever**
- The vault, Touch ID and Secure Enclave protection.
- The CLI and MCP server.
- `.env` injection and clipboard auto-clear.
- Scanning your own folders and configs for plaintext keys.
- Key-type labels and leak-response guides.
- **Encrypted export and backup.** Without it, a lost Mac means lost recovery codes.
- Commercial use of the free core.

**Pro (paid)**
- End-to-end encrypted iCloud sync. SecretKit gives this away, so price Pro as a bundle, not as "sync".
- Client workspaces with handoff packages and "forget this client".
- Share with one person, with expiry.
- An access log with CSV/PDF export.
- Rotation reminders and a key-age dashboard.
- Service presets that link to each provider's rotation page.
- Priority support.

**Gating under MIT.** Keep all crypto and storage code open. Pro unlocks features in the official signed build with a license key; building from source gets everything. Maccy does roughly this ([Maccy](https://github.com/p0deje/Maccy)).

**Say no to crypto wallet seeds.** Detect 12- or 24-word BIP-39 phrases and decline gently. Make the MCP server refuse anything tagged as a recovery code or seed.

## 4. Business model

### Comparable pricing

| App | Model |
|---|---|
| Secretive | Free, open source, attested builds ([GitHub](https://github.com/maxgoedjen/secretive)) |
| NoxKey / PassStore / SecretKit | Free (AGPL) / free (MIT) / free with tips |
| CleanShot X | $29 one-time with 1 year of updates, then $19/yr ([CleanShot](https://cleanshot.com/buy)) |
| TablePlus | $99 per device, $59/yr renewal ([TablePlus](https://tableplus.com/pricing)) |
| Proxyman | $69 perpetual with 1 year of updates ([Proxyman](https://proxyman.com/pricing)) |
| Raycast | Free. Pro $8–10/mo ([Raycast](https://www.raycast.com/pricing)) |
| Tower | $69–129/yr ([Tower](https://www.git-tower.com/pricing)) |
| Kaleidoscope | $8/mo billed yearly ([blog](https://blog.kaleidoscope.app/2023/03/23/switching-to-subscription-pricing-for-kaleidoscope-4/)) |

**Team secret managers:**
- 1Password Business: $8.99/user/mo ([Vendr](https://www.vendr.com/marketplace/1password)).
- Doppler: free for 3 users, then $21/user ([Doppler](https://www.doppler.com/pricing)).
- Infisical: free for 5 identities, then $18 per identity ([Infisical](https://infisical.com/pricing)).
- Bitwarden Secrets Manager: free for 2 users, then $6–12/user ([Bitwarden](https://bitwarden.com/help/secrets-manager-plans/)).

**Recommended: free core plus one-time Pro, matching Binky**
- Pro at $15 one-time with 1 year of updates, then $5/yr. Covers the owner's Macs, commercial use included.
- A family bundle of about $25 (Dinky, Binky Pro and Slinky Pro), and a household tier at about $40.
- Later, a Studio tier for up to 5 people at about $39/yr.
- Sell direct and through Homebrew first. The App Store is optional.

**Alternative 1: fully free, sponsor-funded.** GitHub Sponsors, a tip jar and sponsorware ([Porzio](https://calebporzio.com/sponsorware)). Maximum trust, low revenue, and it works as a funnel for Binky Pro.

**Alternative 2: Setapp plus direct sales.** Revenue depends on how often people open the app, and a vault is used in short bursts ([Setapp](https://docs.setapp.com/docs/setapp-membership-revenue)).

**Trust requirements:**
- Attested and notarized builds.
- No network access by default, and no telemetry.
- A SECURITY.md with private vulnerability reporting.
- An open export format.
- A public threat model.
- A third-party audit once revenue allows.

## 5. Messaging

**Principles by audience:**
- Non-technical builders: talk about consequences, not jargon.
- Developers: talk about mechanism.
- Freelancers: talk about professionalism.
- Everyone: no fear-selling, no exclamation points.

**Lines:**
1. Slinky keeps secrets out of files.
2. Your agent gets the key's effect, not the key.
3. The AI can use it. It just can't read it.
4. For the key you pasted into a chat once and have thought about since.
5. Some keys are fine in a browser. Slinky tells you which ones.
6. Finish the project. Hand over the keys. Forget them properly.
7. One client per drawer. Nothing leaks between them.
8. Touch ID for the live keys. Nothing for the test ones.
9. Quietly in the background, where secrets belong.
10. No account, no cloud, no telemetry. Just your Mac, being careful.
11. When a key leaks, Slinky tells you which door to lock first.
12. It won't store your crypto seed. That's us being polite.

## 6. Risks
1. **Commoditization.** NoxKey, PassStore, SecretKit and 1Password cover the core. Differentiate on design, plain language and freelancer workflows.
2. **Platform absorption.** Agent vendors are adding credential stripping, and 1Password and Anthropic are partnering.
3. **Overclaiming.** Say "out of context and out of files", not "safe from agents".
4. **A single point of loss.** Free backup is required.
5. **Solo-developer trust and bus factor.** Answer with open source, attested builds and an open export format.
6. **Support load.** Scope it clearly: Slinky stores keys, it doesn't audit apps.
7. **Revenue.** The category norm is free, so expect family-bundle revenue, not a standalone business.
8. **Liability optics.** Keep copy factual, and point leak guides to the providers' own documentation.
