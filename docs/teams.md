# Slinky for teams

First written 2026-10-22 as thinking. Built 2026-10-29 (1.6) after [issue #1](https://github.com/heyderekj/slinky/issues/1): "During development with a team it would be great to share stuff." This is the design as built.

## The short version
- No server and no account. Each Mac has a **sharing card**: public keys whose private halves stay in that Mac's Secure Enclave.
- **Share with a person:** a `.slinkyshare` file sealed to the cards you pick. You send it however you like.
- **Shared projects:** one `.slinkyproject` file per project, in a folder the team already syncs (shared iCloud Drive, Dropbox, a NAS). Every member's Mac reads it, merges it variable by variable, and writes it back.
- Slinky makes **no new network request**. As with vault sync, the person's own sync service moves the files.

## Keys (`SlinkyCoreVault`)
- **`SharingIdentity`** (`Sharing.swift`): four Secure Enclave keys per Mac, each in a login-keychain item only Slinky reads silently.
  - P-256 key agreement and P-256 signing on every Mac.
  - ML-KEM-768 and ML-DSA-65 on macOS 26 and later.
  - Opening (agreement, KEM) needs Touch ID.
  - Signing doesn't, because every save to a shared project is signed. The app asks for Touch ID first for everything a person does on purpose: sharing, and adding or removing people.
- **`PersonCard`**: id (from the signing key), name, public keys, date.
  - Text form: `slinky-card:v1:<base64url>`. File form: `.slinkycard`.
  - The **code** is SHA-256 of the keys, 80 bits, shown as 4×4 Crockford characters with the same formatting as the Recovery Key. People compare it on a call or in person, in the Add Person panel ("It Matches" / "It Doesn't Match"); People shows "Code compared" or a Compare Code… button.
- **Hybrid envelope** (`KeyWrapping.swift`, `Envelope`):
  - Ephemeral P-256 ECDH plus ML-KEM-768 encapsulation. Both secrets go through HKDF-SHA256, bound to both ciphertexts and the recipient's public keys, then AES-GCM.
  - Layout `0x48 'H' | 1 | ephemeral (65) | KEM ciphertext (1088) | box`.
  - Classic envelopes start `0x04`, so old blobs still open.
  - A recipient without an ML-KEM key (a Mac on macOS 15) gets a classic envelope.
- **Signatures:** P-256 ECDSA, plus ML-DSA-65 when the card has an ML-DSA key. When it does, both are required, so the post-quantum one can't be stripped.

## The vault uses the same envelope
On macOS 26 and later, `EnclaveWrapper` adds a Secure Enclave ML-KEM key and wraps the vault key hybrid.
- An older vault moves to the hybrid lock the first time it's unlocked (`VaultStore.unlock(context:)`, `needsRewrap`).
- Unwrapping evaluates the `LAContext` once (`askOnce`), so it's one Touch ID for two keys.
- `VaultFile.version` stays 1. Backups and sync copies carry no Secure Enclave wrap.
- Going back to an older Slinky means unlocking once with the Recovery Key.
- The Recovery Key is symmetric (HKDF plus AES-GCM) and unchanged.

## Share with a person
- `ShareFile` holds:
  - in the clear: the sender's card, the date, and `[{card id, sealed content key}]`;
  - encrypted: the items (`SharedItems`) under the content key, with AES-GCM;
  - the sender's signatures over the whole file.
- The sender's own card is always a recipient, so they can open their copy.
- Receiving: the file is checked, then opened with Touch ID, then shown in a review panel. Each item gets a new id. Variables go into a project.
  - A card not in People, or one whose code hasn't been compared, gets a plain warning with the sender's code.
- There's no expiry: Slinky couldn't enforce one honestly. The Share panel offers "Remind me to make new keys" on a date instead (a notification, names only).

## Shared projects
`SharedProjectFile` (`SharedProject.swift`) holds:
- the project id;
- `members: [{name, cards}]`;
- the project key, sealed to every card;
- an `epoch`;
- a **members signature** by a member;
- the payload (the project minus folders, AES-GCM with the project id as AAD);
- a **writer signature** by whoever saved it last.

**Checks** on every read (`check(against:)`):
- both signatures are valid;
- the writer is a member;
- if the member list or epoch changed, it was signed by someone in the list this vault already knew, and the epoch didn't go backwards;
- the copy isn't older than one already seen (a rollback or a slow sync). When it is, Slinky writes its own copy back.
- When joining, the member list must be signed by one of its own members. Slinky shows who shared it and whether their code was compared.

**Keys and recovery:**
- The project key (`ProjectSharing.key`) lives in each member's own vault.
- Your Recovery Key and your own sync therefore recover your team access. There's no team recovery key and no 2-of-3 split, which the 10-22 draft proposed.
- A new Mac of yours reads at once, because the key arrives through your own vault sync. Writing waits until a member adds its card ("Add Their Other Mac"). That approval happens in the app, never by email.

**Removing someone:**
- A new key and `epoch + 1`, sealed only to the members who remain.
- Members who read the new file see "Open with Touch ID" to take the new key.
- Then a **Make New Keys** checklist (`RotationChecklistSheet`) lists the project's secrets, with each service's key page.

**Other rules:**
- **Merging:** `VaultMerge.mergeProject`, variable by variable, newer change wins. `Variable.updatedBy` shows "Changed by Ana".
- **Files:** `SharedProjects` watches each file with `NSFilePresenter`, and reads and writes through `CoordinatedFile` (shared with `VaultSync`). It merges "conflicted copy" files and moves them to the Trash.
- **Agents:** `AgentPolicy` stays per variable and applies to everyone. Sharing and People are not in the CLI or MCP.

## What it doesn't protect against (say it plainly)
- A member keeps what they saw or copied. Removal changes the key; it can't make anyone forget.
- Anyone who can write to the team folder can delete the file or put an older copy back. Slinky refuses older copies it has already moved past, but can't stop a deletion. Keep backups.
- An old share file or an old project file opens for whoever it was sealed to.
- Signing keys don't ask for Touch ID on each use. Anything that can run as Slinky's signed code could sign. The same holds for every other key Slinky uses silently.
- Members' names and public cards, the project id and dates are in the clear inside the file, and the file is named after the project. Values and variable names are not.

## How others do it (October 2026)
| | Who can decrypt | How recovery works |
|---|---|---|
| **1Password Business** | Members' devices | A Recovery group holds every vault key and re-seals them for a member's new key. Only members can add people to it. If the group ever has no members, data can't be recovered. |
| **Bitwarden Enterprise** | Members' devices | Each enrolled member's key is sealed to the organization's public key. Admins can reset a member's master password without seeing the old one, without bypassing two-step login, and with every reset logged. |
| **Doppler** | Doppler's service, with an optional customer-held key on enterprise plans | Server-side. Easy, because the service can decrypt. |
| **Infisical** | Originally members' devices, with a printed backup key. It now also offers server-side encryption with one root key. | Depends on the mode. Lose the root key and everything is gone. |
| **Slinky** | Members' Macs | Each member's own Recovery Key, because the project key is in their vault. Losing every member's vault and Recovery Key loses the project. |

Sources:
- [1Password business security practices](https://support.1password.com/business-security-practices/)
- [Bitwarden Account Recovery](https://bitwarden.com/help/account-recovery.md)
- [Doppler security](https://www.doppler.com/security)
- [Infisical security internals](https://infisical.com/docs/internals/security)

## Open questions for Derek
- Pricing: sharing is free in this build, like the rest of Slinky. `docs/research-personal-commercial.md` had "share with one person" under Pro.
- Should a team be able to hold a project without the person who started it? Today any member can add and remove people.
- Site copy: the comparison table row "Share with your team" and the "Unless you share it" note need your OK before `main`.
