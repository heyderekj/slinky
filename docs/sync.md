# Sync

Slinky's vault, the same on each of your Macs, without Slinky ever seeing a server and without any server ever
seeing a value.

## What's built (1.5)

- **A sync folder.** Settings › Sync › Choose Folder…. Slinky writes `<folder>/Slinky/vault.slinky`: the same file
  as a backup (`VaultStore.syncCopy`), with the payload sealed by the vault key and the vault key wrapped only by
  the Recovery Key. There's no Touch ID key in it, so nothing on the other end can open it without the printed
  key. The person's own sync service (iCloud Drive, Dropbox, Syncthing, a NAS) moves the file. Slinky makes no
  network request.
- **Another Mac.** Choosing the same folder finds a vault that this Mac's key can't open. Settings asks for its
  Recovery Key once (`VaultStore.adopt`), folds this Mac's items in, wraps the synced vault key for this Mac's
  Secure Enclave, and keeps the replaced vault as `vault.slinky.previous`. This Mac's old Recovery Key stops
  working; the UI says so.
- **Keeping in step** (`VaultSync`). Every save on this Mac writes the copy a moment later (a burst of edits goes
  out once), reading and merging first. Unlocking, bringing Slinky forward and `NSFilePresenter` change notices
  read it. All file access goes through `NSFileCoordinator`. iCloud placeholders are downloaded first.
  "Conflicted copy" files that open with the vault key are merged in, then moved to the Trash.
- **Merging** (`VaultMerge`, pure and tested). Item by item, matched by id:
  - the newer change wins (edits are dated in `AppModel.change` by `stampChanges`; projects merge their
    variables one by one);
  - a deletion (Recently Deleted) beats older edits and loses to newer ones, so restoring wins;
  - ids deleted for good are kept in `VaultDocument.removed` and never come back;
  - used recovery codes and Activity combine;
  - a newer Recovery Key made on another Mac is taken (`recoverySet` in the vault file).
  Merges are saved as found, never re-dated, so two Macs don't keep bumping each other.
- **Undo** dates what it puts back, so a synced copy can't undo the undo.

## What isn't

- **Two Macs editing the same item within the same second.** The later save wins that item.
- **Recently Deleted entries purged after 30 days on one Mac** can reappear in Recently Deleted from another Mac
  until it purges them too. They never come back into the vault.
- **Settings, sounds, Quick Access shortcut** are per Mac, not synced.

## Later: your own storage

The sync copy is one encrypted blob, so any place that can hold a blob and say when it changed works. Two
connectors would cover most people:

- **Postgres** (your own, Supabase, Neon, RDS): one table, `slinky_vaults(id text primary key, version bigint,
  updated_at timestamptz, vault bytea)`. Optimistic writes (`update … where version = $old`), `LISTEN/NOTIFY` for
  changes. Apple frameworks have no Postgres driver, so this means writing the wire protocol over Network.framework
  (TLS, SCRAM-SHA-256 with CryptoKit), as the MCP server was written by hand. One protocol, not every database.
- **S3-compatible** (AWS, Cloudflare R2, Backblaze B2, MinIO): one object, `If-Match` ETags for safe writes,
  SigV4 signing with CryptoKit, URLSession.

Both need: Derek's OK for the new network requests, honest copy ("your server stores data it can't read"), and
credentials kept in the vault's own keychain item, not UserDefaults. The merge, adoption and Recovery Key rules
above stay exactly the same.
