# Slinky for teams (thinking, not planned)

Written 2026-10-22. Teams isn't on the roadmap, and nothing here changes what Slinky does or promises today. Slinky is one person's vault on one Mac. This note is for the day a team asks to share it.

## The question
A shared home for secrets lowers the chance of leaks: no keys pasted in chat, no `.env` files mailed around. What is hardest to make safe for a team: who can open what (access), copies kept in case something breaks (backups), or getting back in when someone loses their Mac or leaves (recovery)?

## The answer: recovery
- **Access** is well understood. The one hard part is removing someone, because you can take away their access but not what they already saw.
- **Backups** come almost free once everything is end-to-end encrypted. A backup is just ciphertext.
- **Recovery** pulls against Slinky's main promise, that only you can open your vault. Every way of getting someone back in is also a way for someone else to get in. It's also used rarely, so it's rarely tested and quietly stops working.

Recovery has to be designed first. It decides the key model, the access rules follow from that, and backups follow from both.

## What Slinky does today
`SlinkyCoreVault` keeps one vault key and locks it two ways (`VaultStore.swift`):
- to this Mac's Secure Enclave key, opened with Touch ID (`enclaveWrappedKey`);
- to the printed Recovery Key (`recoveryWrappedKey`, `RecoveryKey.swift`).

Locking a key to a Secure Enclave key is `Envelope.seal(_:to:)` in `KeyWrapping.swift`. It seals a secret to any P-256 public key, which is exactly the building block a team version needs.

## The key model
- **Each member** makes a key pair in their own Mac's Secure Enclave. The private half never leaves that Mac. The public half is shared with the team.
- **Each shared vault**, say one project's variables, has its own vault key. That key is sealed separately to every member who has access, with the same `Envelope.seal`.
- **Whatever syncs the vaults** stores only ciphertext and sealed keys. It can never decrypt anything.
- **At least two members** must hold every shared vault, so no secret depends on one Mac.

## Access
- **Adding someone:** a member who already holds the vault key seals it to the new member's public key. No server can add people, only members who hold the key. 1Password works the same way.
- **Removing someone:**
  1. Make a new vault key and seal it to the members who remain.
  2. Then the honest part: removal can't make anyone forget what they saw or copied. So removing a member opens a **"make new keys" checklist**: "Ana could see these 14 keys. Make new ones."
  3. This reuses the rotation helper (`AppModel.startRotation`, `replaced(_:with:)`, `Service.tokenURL`). It opens each service's key page, the person pastes the new key, and every project using it updates.
- **Agents:** `AgentPolicy` (Agents can use, Ask every time, Never leaves) stays per item and applies to every member. Live keys stay held back from agents, as they are now.

## Recovery
This is the core of the design.

**Team recovery key, split 2 of 3.**
- One team recovery key is sealed to every shared vault, the way today's printed Recovery Key is.
- It's split into three parts so that any two can rebuild it. Each part is printed and held by a different named person.
- No single person can recover alone, and losing one part isn't fatal.

**Approval in the app, never an email link.**
- To recover a member, another member approves the request in Slinky after seeing who's asking, from which Mac.
- An email reset is how recovery gets hijacked. 1Password warns not to give recovery rights to whoever runs company email. Bitwarden makes sure a reset doesn't bypass two-step login. Slinky should not depend on email at all.

**A regular check that recovery works.**
- A reminder, say twice a year, to test that two parts still rebuild the key.
- Recovery that's never tried quietly breaks. Infisical's self-hosting guidance warns that losing the root key makes every secret permanently unreadable.

**The honest trade-off.** If two of the three holders work together, they can recover anyone's access. That is the price of not losing everything when one Mac dies. The copy has to say so plainly.

## Backups
- Encrypted backups can live anywhere: iCloud Drive, a shared drive, a USB stick.
- The one catch: an old backup is still sealed to the members it had then. A removed member who kept a copy of an old backup can still open it. The answer is making new keys, not anything clever in the backups.

## Sync
- A team needs sync, and Slinky has none today. `docs/plan.md` already lists CloudKit sync, encrypted before it leaves the Mac, under Tier 2.
- A team version would use CloudKit sharing (`CKShare`) and store only ciphertext and sealed keys. That needs a paid Developer ID.

## What would change in Slinky's promises
- **Site and Help:** "Encrypted on this Mac", "Stays on your Mac" and the comparison table (`site/src/data/compare.ts`, `llms.txt`, Help) would need honest team wording: encrypted on each member's Mac and synced as ciphertext Apple can't read.
- **CLAUDE.md network rules:** these list every request Slinky makes. Sync would be a new one and needs Derek's OK.
- **Copy:** must say what this does **not** protect against:
  - a member who copies a value;
  - two recovery holders working together;
  - an old backup a former member kept.

## How others do it (October 2026)
| | Who can decrypt | How recovery works |
|---|---|---|
| **1Password Business** | Members' devices | A Recovery group holds every vault key and re-seals them for a member's new key. Only members can add people to it. If the group ever has no members, data can't be recovered. |
| **Bitwarden Enterprise** | Members' devices | Each enrolled member's key is sealed to the organization's public key. Admins can reset a member's master password without seeing the old one, without bypassing two-step login, and with every reset logged. |
| **Doppler** | Doppler's service, with an optional customer-held key on enterprise plans | Server-side. Easy, because the service can decrypt. |
| **Infisical** | Originally members' devices, with a printed backup key. It now also offers server-side encryption with one root key. | Depends on the mode. Lose the root key and everything is gone. |

Sources:
- [1Password business security practices](https://support.1password.com/business-security-practices/)
- [1Password Community on account keys](https://1password.community/discussion/comment/355311)
- [Bitwarden Account Recovery](https://bitwarden.com/help/account-recovery.md)
- [Doppler security](https://www.doppler.com/security)
- [Infisical security internals](https://infisical.com/docs/internals/security)

Slinky's path is the device-held family, like 1Password and Bitwarden, with recovery that needs two people instead of trusted admins.

## Open questions for Derek
- Is 2 of 3 the right split, or should the team choose it?
- Who can create a team and add the first members?
- Pricing: Slinky is free. Is a team version free too?
- Does this wait for a Developer ID (Tier 2), since sync needs one?
- Is it one team per vault, or one vault per project shared with chosen people?
