# Slinky in the cloud-agent era

*Research as of 2026-09-24. Sources are linked inline.*

## Executive summary

- **Cloud agents have split into two ways of handling secrets.**
  - (a) The platform puts the secret into the sandbox as an env var, sometimes with redaction: Cursor, Jules, Devin, E2B, Copilot, and Claude Code on Team/Enterprise.
  - (b) An egress proxy outside the VM attaches the credential, so the agent never holds it: Claude Code cloud "API credentials" (Pro/Max), Vercel Sandbox, Cloudflare Sandboxes, Daytona, Modal, and Claude Managed Agents vaults.
  - Pattern (b) is winning. Its weak spot is the human side: someone still pastes the real value into each vendor's dashboard.
- **The real risk is on record.** "Comment and Control" (April 2026) got Claude Code Security Review, Gemini CLI Action and Copilot Agent to post CI secrets as PR comments. Claude Code commits leak secrets at 3.2%, against a 1.5% baseline (GitGuardian).
- **Convex's "sandbox" talk is mostly about Components**, which it calls "sandboxed building blocks." For agents, Convex offers per-agent dev deployments with scoped deploy keys. It has no product for secrets inside cloud sandboxes. Its deploy-key model is the cleanest "mint a scoped key per agent" example to build on.
- **Slinky's best cloud position is to be the human's source of truth and ledger, not a runtime.** It holds root keys, mints or pushes scoped child keys, records where each value went, detects leaks by exact value, and drives rotation.
- **Minting scoped keys is feasible today** for Convex, Cloudflare (with TTL), OpenAI (project service accounts), AWS (STS) and GitHub (App installation tokens). It is not possible through an API for Anthropic keys or GitHub fine-grained PATs.
- **A Mac approval broker for cloud agents should come later.** It needs a relay, and Bitwarden (Agent Access SDK) and 1Password are building one.
- **Local-first isn't going away.** Claude Code Remote Control and self-hosted environments, Codex local, and 1Password's local Codex integration all keep the Mac in the loop.

## 1. How secrets get into cloud agents today

| Platform | Mechanism | Notes |
|---|---|---|
| Claude Code cloud | Env vars, a setup script, and on Pro/Max "API credentials" attached by Anthropic's proxy for hosts you list. The key "never reaches Claude, the commands it runs, or the session's environment variables." | Team/Enterprise don't have API credentials yet. No edit: delete and re-add ([docs](https://code.claude.com/docs/en/cloud-environments), [#32733](https://github.com/anthropics/claude-code/issues/32733)) |
| Claude Code local sandbox | `sandbox.credentials` `mode: "mask"`: commands see a sentinel, and the proxy swaps in the real value only for `injectHosts`. Needs `network.tlsTerminate`. | Only honored from user or managed settings, never from the repo ([docs](https://code.claude.com/docs/en/sandboxing)) |
| OpenAI Codex cloud | Secrets are available only to setup scripts and removed before the agent phase. | Agent internet is off by default ([docs](https://learn.chatgpt.com/docs/environments/cloud-environment)). A rumored new Codex Cloud has proxy-delivered secrets and OIDC ([RuntimeWire](https://runtimewire.com/article/openai-is-preparing-a-new-codex-cloud-with-tailscale-and-azure-workload-identity)) |
| Cursor cloud agents | Three types: Environment Variable, Runtime Secret (redacted in output and transcripts), Build Secret. | Warns about prompt-injection exfiltration ([docs](https://cursor.com/docs/cloud-agent/security-network)) |
| GitHub Copilot cloud agent | The `copilot` environment or "Agents" secrets (org-level since May 2026). Firewall on by default. | [changelog](https://github.blog/changelog/2026-05-08-more-flexible-secrets-and-variables-for-copilot-cloud-agent/) |
| Jules | Repo env vars, opted in per task. | [changelog](https://jules.google/docs/changelog/2025-10-01/) |
| Devin | Org secrets, plus session secrets it asks for in chat. | [docs](https://docs.devin.ai/product-guides/secrets) |
| E2B | Plain env vars, readable inside the sandbox. | [docs](https://e2b.dev/docs/sandbox/environment-variables) |
| Daytona | Opaque placeholders, swapped in by an egress proxy. Omitting hosts means any host. | [docs](https://www.daytona.io/docs/en/secrets/) |
| Modal | Sidecar proxy; the sandbox gets a short-lived JWT. | [recipe](https://github.com/modal-labs/credential-injection) |
| Vercel Sandbox | Firewall header injection ("credentials brokering"). | [changelog](https://vercel.com/changelog/safely-inject-credentials-in-http-headers-with-vercel-sandbox) |
| Cloudflare Sandboxes | Outbound Workers inject credentials, with a per-sandbox CA (April 2026 GA). | [blog](https://blog.cloudflare.com/sandbox-auth/) |
| Claude Managed Agents | Vaults, substituted at egress. | [docs](https://platform.claude.com/docs/en/managed-agents/vaults) |
| App builders | Lovable, Bolt and Replit use dashboard panes. Convex Chef uses Convex deployment env vars. | 170 of 1,645 Lovable apps exposed keys ([Wavect](https://wavect.io/blog/lovable-bolt-replit-app-due-diligence/), [Chef](https://github.com/get-convex/chef)) |

**Documented risks:**
- Comment and Control ([VentureBeat](https://venturebeat.com/security/ai-agent-runtime-security-system-card-audit-comment-and-control-2026)).
- CamoLeak, CVE-2025-59145 ([DEV](https://dev.to/waxell/ai-coding-agent-prompt-injection-the-cicd-credential-risk-2026-54if)).
- GitGuardian 2026: 1.27M leaked AI-service secrets, up 81%, and 24,008 secrets in MCP configs ([GitGuardian](https://blog.gitguardian.com/the-state-of-secrets-sprawl-2026/)).

## 2. Convex specifically

- **Components as sandboxes** (Series B, 4 Aug 2026): "sandboxed building blocks." An agent "can't reach across the boundary." Nothing about secrets ([news](https://news.convex.dev/convex-raises-57m/)).
- **Agent Mode.** For cloud agents that "can't log in," the CLI runs an anonymous local backend, or `npx convex deployment token create agent-token --save-env` mints a key limited to the agent's own dev deployment ([docs](https://docs.convex.dev/cli/agent-mode), [multiple deployments](https://docs.convex.dev/production/multiple-deployments)).
- **Deploy keys** are scoped per action (deploy, logs, data, env vars). No expiration is documented ([docs](https://docs.convex.dev/cli/deploy-key-types)).
- **Env vars** are per deployment, with project defaults per deployment type, `npx convex env set --from-file`, or typed declarations in `convex.config.ts`. Limits: 512 vars, 8 KiB each ([docs](https://docs.convex.dev/production/environment-variables)).
- **Community "Convex Sandbox":** a just-bash shell for agents, "not great for running untrusted compiled binaries" ([Stack](https://stack.convex.dev/convex-sandbox-persistent-bash-environment)).
- **What I couldn't find:** any Convex statement about agent-safe secrets.
- **Takeaway:** Convex is the ideal first minting target: one scoped dev deploy key per agent or worktree, recorded in the ledger and revocable. Push env vars through `convex env set --from-file`.

## 3. Emerging patterns

1. **Egress proxies that inject credentials** are now standard. Open-source options: Infisical Agent Vault ([GitHub](https://github.com/Infisical/agent-vault)), OneCLI ([GitHub](https://github.com/onecli/onecli)), Varlock with host/path rules including `approval` ([docs](https://varlock.dev/guides/proxy/)).
2. **Names only, never values, over MCP.** 1Password's Environments MCP for Codex: "the MCP server does not return secret values" ([1Password](https://1password.com/blog/1password-trusted-access-layer-for-openai-codex)).
3. **Secret intake outside the chat.** The MCP spec forbids form-mode elicitation for API keys and requires URL mode ([spec](https://modelcontextprotocol.io/specification/2025-11-25/client/elicitation)).
4. **Approval on a device.** Bitwarden's Agent Access SDK (open, alpha) ([blog](https://bitwarden.com/blog/introducing-agent-access-sdk/), [GitHub](https://github.com/bitwarden/agent-access)), and OIDC CIBA ([Auth0](https://auth0.com/blog/secure-ai-stop-managing-api-keys-by-hand/)).
5. **Short-lived credentials.**
   - Anthropic supports Workload Identity Federation and `expires_at` ([Admin API](https://platform.claude.com/docs/en/manage-claude/admin-api)).
   - Stripe has agent-tagged restricted keys with approval rules ([Stripe](https://docs.stripe.com/keys)).
   - Keycard offers ephemeral task-scoped credentials.
6. **Setup-phase-only secrets:** Codex, and Cursor Build Secrets.

## 4. Local-vault ideas, evaluated

**A. Push to cloud targets plus a "where does this key live" map.**
- *Feasible now* by API or CLI: Vercel, Netlify, Convex, Cloudflare `wrangler secret put`, GitHub Actions (libsodium sealed box, [docs](https://docs.github.com/en/rest/guides/encrypting-secrets-for-the-rest-api)), Codespaces ([docs](https://docs.github.com/en/rest/codespaces/repository-secrets)), and Copilot Agents secrets.
- *Not feasible by API:* Claude Code cloud credentials, Codex cloud and Cursor secrets. For these, use deep-link plus copy-once and a "mark as placed" record.
- *Risks:* many provider write tokens held in one place, and a map that goes stale when values change in dashboards.

**B. Mint scoped or short-lived keys instead of handing over the root key.**

| Provider | Scoped key via API | TTL |
|---|---|---|
| Convex | Yes, per-deployment deploy key | Not documented |
| Cloudflare | Yes, `expires_on` and IP conditions ([docs](https://developers.cloudflare.com/fundamentals/api/how-to/create-via-api/)) | Yes |
| OpenAI | Yes, project service account; needs an Admin key ([ref](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/projects/subresources/service_accounts/methods/create)) | No; revoke by deleting |
| AWS | STS AssumeRole | Yes |
| GitHub | App installation tokens (1 hour); fine-grained PATs are UI only | Yes |
| Stripe | Restricted keys in the Dashboard; the API route is for Stripe Apps only | Expire or scheduled rotation |
| Anthropic | No, keys are created in the Console | Yes, via the Console |
| Supabase | Multiple revocable `sb_secret_` keys; API creation unconfirmed ([docs](https://supabase.com/docs/guides/getting-started/api-keys)) | — |

Minting needs the admin credential, so require Touch ID on every mint.

**C. A Mac approval broker for cloud agents.** Later. It needs a relay and phone/Watch push, and the value should go to a proxy or a minted key. The risks are infrastructure cost, attack surface, and the Mac being asleep. Explore acting as a Bitwarden Agent Access provider first; that interop is unverified.

**D. Rotation assist after a session.** v1. A local ledger records pushes, mints and injections, then prompts: "3 keys were exposed to Cursor cloud for 2 hours. Rotate?" It deep-links to each provider's rotate page.

**E. Exact-value leak scanning of exported transcripts, logs and git history.** v1. Also check base64 and URL-encoded forms. Match in memory only.

**F. Generate proxy configs.** Claude Code `sandbox.credentials` mask entries go in user settings, since repo settings are ignored for masks.

**G. A names-only env manifest committed to the repo.** Name, provider, scopes and allowed hosts. Align it with Varlock's `.env.schema` rather than inventing a new format.

**H. Send OAuth tools elsewhere.** GitHub goes through Anthropic's proxy, and OAuth tools go through Arcade, Composio or MCP OAuth. Slinky handles raw keys and recovery codes.

## 5. Competitive read
- **1Password:** Unified Access, the Environments MCP for Codex and Cursor, and just-in-time injection. The closest overlap, but paid and aimed at teams.
- **Bitwarden:** the Agent Access SDK, with OneCLI integration ([OneCLI](https://onecli.sh/blog/bitwarden-agent-access-sdk-onecli)).
- **Doppler and Infisical:** team platforms. Infisical also has the open-source Agent Vault.
- **Varlock and OneCLI:** open-source developer proxies. Varlock is the nearest indie competitor. Neither is native to Mac or uses the Secure Enclave.
- **Keycard and Aembit:** enterprise agent identity ([SecurityWeek](https://www.securityweek.com/keycard-emerges-from-stealth-mode-with-38-million-in-funding/)).
- **Arcade, Composio and Smithery:** OAuth runtimes. They complement Slinky.

**Read:** A free native Mac app can credibly be the solo developer's vault and ledger, upstream of every cloud proxy. The proxies need a human to feed them; none tracks where values went across vendors or mints scoped keys across providers for individuals.

## Ranked features and positions for the cloud-agent era
1. **Exposure ledger and rotation assist.** v1.
2. **Mint instead of share:** Convex first, then Cloudflare, OpenAI, AWS and GitHub App tokens. v1.x. Touch ID on every mint.
3. **Push to cloud targets with provenance:** Vercel, Netlify, Convex, Cloudflare, GitHub Actions, Codespaces and Copilot. Guided copy-once for Claude Code, Codex and Cursor. v1.x.
4. **Exact-value leak scanner** for transcripts, logs and repos. v1.
5. **Names-only env manifest plus MCP URL-mode intake.** v1.
6. **Proxy-config generator** for local agents (Claude Code mask entries). v1.
7. **Present hybrid sessions as a feature:** Remote Control and self-hosted environments keep the full Touch ID model ([Anthropic](https://claude.com/blog/run-claude-code-sessions-on-your-own-compute)). v1, mostly docs.
8. **Approve from iPhone or Watch through a relay**, with values going to a proxy or a minted key. Later.
9. **Offline root of trust** for recovery codes and provider admin credentials. v1.

## What Slinky should NOT try to be
- A hosted vault, sync service or team secrets platform.
- A cloud egress proxy or sandbox operator.
- An enterprise agent-identity product.
- An OAuth broker.
- A regex scanner competing with GitGuardian.
- Anything that returns values to a model, "just this once" included.
