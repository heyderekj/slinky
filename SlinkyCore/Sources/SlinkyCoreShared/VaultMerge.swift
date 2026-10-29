import Foundation

/// Sync: two copies of the same vault, edited on two Macs, become one. Works item by item: the newer change to
/// each item wins, deletions beat older edits (and lose to newer ones), and items deleted for good never come
/// back. Pure and in memory; the vault's own code does the decrypting and encrypting around it.
public enum VaultMerge {
    /// `local` wins exact ties, so merging a copy with itself changes nothing.
    public static func merge(_ local: VaultDocument, _ remote: VaultDocument) -> VaultDocument {
        var out = local
        out.formatVersion = max(local.formatVersion, remote.formatVersion)

        var removed = local.removed ?? [:]
        for (id, date) in remote.removed ?? [:] { removed[id] = max(removed[id] ?? .distantPast, date) }
        out.removed = removed.isEmpty ? nil : removed

        // Recently Deleted: every entry from both, one per item (the latest deletion).
        var trash: [UUID: TrashEntry] = [:]
        for entry in local.trashed + remote.trashed {
            if let have = trash[entry.item.itemID], have.deletedAt >= entry.deletedAt { continue }
            trash[entry.item.itemID] = entry
        }

        out.keys = list(local.keys, remote.keys, stamp: \.updated)
        out.codeSets = list(local.codeSets, remote.codeSets, stamp: { $0.modified ?? $0.created }) { winner, other in
            // A code crossed off on either Mac stays crossed off, as long as they're the same codes.
            guard winner.codes == other.codes else { return winner }
            var merged = winner
            merged.used.formUnion(other.used)
            return merged
        }
        out.kept = list(local.kept, remote.kept, stamp: { $0.modified ?? $0.created })
        out.secretFiles = list(local.secretFiles, remote.secretFiles, stamp: \.updated)
        out.projects = list(local.projects, remote.projects, stamp: { $0.modified ?? $0.created }, combine: combineProjects)
        out.people = list(local.people, remote.people, stamp: { $0.modified ?? $0.added }) { winner, other in
            // Every Mac's card stays, whichever copy changed the name last.
            var merged = winner
            merged.cards = list(winner.cards, other.cards, stamp: \.made)
            return merged
        }

        // Settle deletions against edits: whichever happened later wins.
        func gone(_ id: UUID, _ stamp: Date) -> Bool {
            if let date = removed[id], date >= stamp { return true }
            if let entry = trash[id], entry.deletedAt >= stamp { return true }
            if trash[id] != nil { trash[id] = nil }   // edited (or restored) after it was deleted: the edit wins
            return false
        }
        out.keys.removeAll { gone($0.id, $0.updated) }
        out.codeSets.removeAll { gone($0.id, $0.modified ?? $0.created) }
        out.kept.removeAll { gone($0.id, $0.modified ?? $0.created) }
        out.secretFiles.removeAll { gone($0.id, $0.updated) }
        out.projects.removeAll { gone($0.id, $0.modified ?? $0.created) }
        for i in out.projects.indices { out.projects[i].variables.removeAll { gone($0.id, $0.updated) } }
        out.people.removeAll { gone($0.id, $0.modified ?? $0.added) }
        // Entries for things deleted for good leave Recently Deleted too.
        out.trashed = trash.values.filter { removed[$0.item.itemID] == nil }.sorted { $0.deletedAt > $1.deletedAt }

        // History: everything from both, newest first.
        var seen = Set<UUID>()
        out.log = (local.log + remote.log).filter { seen.insert($0.id).inserted }.sorted { $0.date > $1.date }

        var icons = remote.siteIcons ?? [:]
        for (domain, png) in local.siteIcons ?? [:] { icons[domain] = png }
        out.siteIcons = icons.isEmpty ? nil : icons
        return out
    }

    /// Two copies of one project (this vault's and a synced or shared one): the newer name, folders and expected
    /// names, and each variable's newer change.
    public static func mergeProject(_ local: Project, _ remote: Project) -> Project {
        let remoteNewer = (remote.modified ?? remote.created) > (local.modified ?? local.created)
        return combineProjects(remoteNewer ? remote : local, remoteNewer ? local : remote)
    }

    static func combineProjects(_ winner: Project, _ other: Project) -> Project {
        var merged = winner
        merged.variables = list(winner.variables, other.variables, stamp: \.updated)
        return merged
    }

    /// Both lists, matched by id. The newer one of a pair wins (`combine` can fold in the other); items only the
    /// other copy has go first, as they're most likely new.
    static func list<T: Identifiable>(_ local: [T], _ remote: [T], stamp: (T) -> Date,
                                      combine: ((T, T) -> T)? = nil) -> [T] where T.ID == UUID {
        var out = local
        var index: [UUID: Int] = [:]
        for (i, item) in local.enumerated() { index[item.id] = i }
        var added: [T] = []
        for item in remote {
            if let i = index[item.id] {
                let mine = out[i]
                let winner = stamp(item) > stamp(mine) ? item : mine
                let other = stamp(item) > stamp(mine) ? mine : item
                out[i] = combine?(winner, other) ?? winner
            } else {
                added.append(item)
            }
        }
        return added + out
    }
}

extension VaultDocument {
    /// After an edit on this Mac: stamps what changed (or is newly back) with `now`, and records ids that are
    /// gone for good, so a merge knows which side's change is newer. Not used for merges themselves, which keep
    /// the dates they found.
    public mutating func stampChanges(since before: VaultDocument, now: Date = .now) {
        func stamp<T: Identifiable & Equatable>(_ items: inout [T], _ old: [T], _ set: (inout T) -> Void) where T.ID == UUID {
            let previous = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
            for i in items.indices where previous[items[i].id] != items[i] { set(&items[i]) }
        }
        stamp(&keys, before.keys) { $0.updated = now }
        stamp(&codeSets, before.codeSets) { $0.modified = now }
        stamp(&kept, before.kept) { $0.modified = now }
        var everyone = people
        stamp(&everyone, before.people) { $0.modified = now }
        people = everyone
        var files = secretFiles
        stamp(&files, before.secretFiles) { $0.updated = now }
        secretFiles = files
        let oldProjects = Dictionary(uniqueKeysWithValues: before.projects.map { ($0.id, $0) })
        for p in projects.indices {
            let old = oldProjects[projects[p].id]
            stamp(&projects[p].variables, old?.variables ?? []) { $0.updated = now; $0.updatedBy = nil }
            if old == nil || old!.name != projects[p].name || old!.folders != projects[p].folders || old!.expected != projects[p].expected
                || old!.sharing?.members != projects[p].sharing?.members || old!.sharing?.epoch != projects[p].sharing?.epoch {
                projects[p].modified = now
            }
        }
        // Gone from everywhere (not just moved to Recently Deleted): deleted for good.
        let gone = before.allIDs.subtracting(allIDs)
        if !gone.isEmpty {
            var removed = self.removed ?? [:]
            for id in gone { removed[id] = now }
            self.removed = removed
        }
    }

    /// Every item and variable id, in the vault or in Recently Deleted.
    var allIDs: Set<UUID> {
        var ids = Set(keys.map(\.id) + codeSets.map(\.id) + kept.map(\.id) + secretFiles.map(\.id) + projects.map(\.id) + people.map(\.id))
        for p in projects { ids.formUnion(p.variables.map(\.id)) }
        for entry in trashed {
            ids.insert(entry.item.itemID)
            if case let .project(p) = entry.item { ids.formUnion(p.variables.map(\.id)) }
        }
        return ids
    }
}
