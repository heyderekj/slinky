import AppKit
import LocalAuthentication
import SlinkyCoreShared
import SlinkyCoreVault

/// Items picked to share, while the Share panel is open. Copies with values, in memory only.
struct ShareDraft: Identifiable, Equatable {
    let id = UUID()
    var items: SharedItems
    /// The project the variables came from, for the panel's title.
    var projectName: String?
}

/// A share opened on this Mac: who it's from (as checked against People) and what's in it. Memory only.
struct ReceivedShare: Identifiable, Equatable {
    let id = UUID()
    var from: PersonCard
    var made: Date
    var items: SharedItems
    /// The person in People with this exact card, if any.
    var known: Person?
}

extension AppModel {
    /// This Mac's sharing keys, in its Secure Enclave.
    nonisolated static let sharingKeys = SharingIdentity()

    /// The name on this Mac's card: what you called yourself in People, or this Mac's account name.
    var myName: String { document.me?.name ?? NSFullUserName() }

    /// This Mac's card (public keys only). nil in a demo vault, or if the Secure Enclave can't make the keys.
    var myCard: PersonCard? {
        guard !isDemoMode else { return nil }
        return try? Self.sharingKeys.card(name: myName)
    }

    /// Adds this Mac's card to your own entry in People, so your other Macs (through sync) and anyone you send
    /// your card to know it. Public keys only; reading them needs no Touch ID.
    func updateMyCard() {
        guard isUnlocked, !isDemoMode, let card = myCard else { return }
        if let me = document.me, me.has(card) { return }
        change { doc in
            if let i = doc.people.firstIndex(where: \.isMe) {
                doc.people[i].cards.removeAll { $0.id == card.id }
                doc.people[i].cards.append(card)
            } else {
                doc.people.append(Person(name: card.name, cards: [card], checked: true, isMe: true))
            }
        }
    }

    func renameMe(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let i = document.people.firstIndex(where: \.isMe), document.people[i].name != name else { return }
        change { $0.people[i].name = name }
        updateMyCard()
    }

    // MARK: People

    /// A card pasted, dropped or opened. Your own card is ignored; a known person's new card (a new Mac) joins them.
    @discardableResult
    func addCard(_ card: PersonCard, checked: Bool = false) -> String {
        if let me = document.me, me.has(card) { return "That's your own card." }
        if let i = document.people.firstIndex(where: { $0.has(card) }) {
            if checked && !document.people[i].checked { change { $0.people[i].checked = true } }
            return "\(document.people[i].name) is already in People."
        }
        var person = Person(name: card.name, cards: [card], checked: checked)
        // The same name already here: probably a new Mac of theirs. Ask before mixing them up.
        if let existing = document.people.first(where: { !$0.isMe && $0.name.caseInsensitiveCompare(card.name) == .orderedSame }) {
            person.name = "\(card.name) (\(card.fingerprint.prefix(4)))"
            change("Added \(person.name). If this is \(existing.name)'s new Mac, add it from their row instead.") { $0.people.append(person) }
            return person.name
        }
        change("Added \(card.name) to People.") { $0.people.append(person) }
        return card.name
    }

    /// A new Mac of someone already in People.
    func addCard(_ card: PersonCard, to personID: UUID) {
        guard let i = document.people.firstIndex(where: { $0.id == personID }), !document.people[i].has(card) else { return }
        change("Added \(document.people[i].name)'s other Mac.") { doc in
            doc.people[i].cards.append(card)
            doc.people[i].checked = false   // the new card's code hasn't been compared yet
        }
    }

    func setChecked(_ personID: UUID, _ checked: Bool) {
        guard let i = document.people.firstIndex(where: { $0.id == personID }) else { return }
        change { $0.people[i].checked = checked }
    }

    func removePerson(_ personID: UUID) {
        guard let person = document.people.first(where: { $0.id == personID }), !person.isMe else { return }
        change("Removed \(person.name) from People. Shared projects they're in don't change until you remove them there too.",
               toastStyle: .removed) { $0.people.removeAll { $0.id == personID } }
    }

    /// A `.slinkycard` file opened or dropped.
    func openCard(_ url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8), let card = PersonCard(text: text) else {
            show("That isn't a Slinky sharing card.", style: .info)
            return
        }
        selection = .people
        beginAddPerson(card)
    }

    /// The Add Person panel: with a card (opened, dropped or pasted), or empty to paste one.
    func beginAddPerson(_ card: PersonCard? = nil) {
        guard isUnlocked else { return }
        guard !panelOpen else { show("Finish or cancel what's open first.", style: .info); return }
        addingPerson = AddPersonDraft(card: card)
    }

    /// Comparing the code of someone already in People.
    func beginAddPerson(comparing person: Person) {
        guard isUnlocked, !panelOpen else { return }
        addingPerson = AddPersonDraft(person: person.id)
    }

    func openSharingSettings(highlighting: String? = nil) {
        sharing = nil
        selection = .people
        openMainWindow?()
    }

    /// Your card as a file, for AirDrop, Messages or Mail. Public keys only.
    func myCardFile() -> URL? {
        guard let card = myCard else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(card.name).slinkycard")
        try? card.text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: Sending

    func beginShare(_ items: SharedItems, projectName: String? = nil) {
        guard isUnlocked, !items.isEmpty else { return }
        guard !panelOpen else { show("Finish or cancel what's open first.", style: .info); return }
        sharing = ShareDraft(items: items, projectName: projectName)
    }

    /// Library items by reference, as copies.
    func sharedItems(_ refs: [LibraryRef]) -> SharedItems {
        var items = SharedItems()
        for ref in refs {
            switch ref {
            case let .key(id): if let k = document.keys.first(where: { $0.id == id }) { items.keys.append(k) }
            case let .codes(id): if let c = document.codeSets.first(where: { $0.id == id }) { items.codeSets.append(c) }
            case let .kept(id): if let k = document.kept.first(where: { $0.id == id }) { items.kept.append(k) }
            case let .file(id): if let f = document.secretFiles.first(where: { $0.id == id }) { items.files.append(f) }
            }
        }
        return items
    }

    /// Seals the draft to the chosen people's cards, after Touch ID. Returns the file, in a private temporary
    /// folder, ready to send any way the person likes.
    func makeShare(_ draft: ShareDraft, to personIDs: Set<UUID>, remindOn: Date?) async -> URL? {
        let people = document.people.filter { personIDs.contains($0.id) }
        let cards = people.flatMap(\.cards)
        guard !cards.isEmpty else { return nil }
        let who = Self.list(people.map(\.name))
        let count = draft.items.count
        guard await approve(reason: "share \(count) \(count == 1 ? "item" : "items") with \(who)") else { return nil }
        let name = myName
        let items = draft.items
        do {
            let data = try await Task.detached {
                try ShareFile.make(items, from: AppModel.sharingKeys, name: name, to: cards, context: nil)
            }.value
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Slinky Shares", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            // The file name says who it's from and for, never what's in it.
            let url = folder.appendingPathComponent("From \(name) for \(who).\(ShareFile.fileExtension)")
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            record(ActivityEntry(action: .shared, names: items.names, detail: who))
            if let remindOn { Reminders.remindToReplace(items.names, sharedWith: who, on: remindOn) }
            return url
        } catch {
            show("Couldn't make the share: \(Self.friendly(error))", style: .info)
            return nil
        }
    }

    // MARK: Receiving

    /// A `.slinkyshare` opened (Finder, AirDrop, a drop). Touch ID, then the review panel.
    func openShare(_ url: URL) {
        guard !isDemoMode else { return }
        guard let data = try? Data(contentsOf: url), let file = try? ShareFile.peek(data) else {
            show("That isn't a Slinky share, or it's damaged.", style: .info)
            return
        }
        guard let card = myCard, file.isFor(card) else {
            show("This wasn't shared with this Mac. Ask \(file.from.name) to share it with your card from this Mac.", style: .info)
            return
        }
        let name = myName
        Task {
            guard await approve(reason: "open what \(file.from.name) shared") else { return }
            do {
                let items = try await Task.detached { try file.open(with: AppModel.sharingKeys, name: name, context: nil) }.value
                receiving = ReceivedShare(from: file.from, made: file.made, items: items, known: document.person(for: file.from))
            } catch {
                show(Self.friendly(error), style: .info)
            }
        }
    }

    /// Saves the picked items from a share: new ids (so they never collide with the sender's), variables into
    /// `project` (a new one named `newProject` when nil).
    func saveReceived(_ share: ReceivedShare, picked: Set<String>, project: UUID?, newProject: String?) {
        var items = share.items
        func keep(_ name: String) -> Bool { picked.contains(name) }
        items.keys = items.keys.filter { keep($0.name) }.map { var k = $0; k.id = UUID(); k.created = .now; return k }
        items.kept = items.kept.filter { keep($0.label) }.map { var k = $0; k.id = UUID(); k.created = .now; return k }
        items.codeSets = items.codeSets.filter { keep($0.account) }.map { var c = $0; c.id = UUID(); c.created = .now; return c }
        items.files = items.files.filter { keep($0.name) }.map { var f = $0; f.id = UUID(); return f }
        let from = share.known?.name ?? share.from.name
        items.variables = items.variables.filter { keep($0.name) }.map { var v = $0; v.id = UUID(); return v }
        guard !items.isEmpty else { return }
        change("Saved \(items.count) \(items.count == 1 ? "item" : "items") from \(from).", activity: ActivityEntry(action: .received, names: items.names, actor: from)) { doc in
            doc.keys.insert(contentsOf: items.keys, at: 0)
            doc.kept.insert(contentsOf: items.kept, at: 0)
            doc.codeSets.insert(contentsOf: items.codeSets, at: 0)
            doc.secretFiles = items.files + doc.secretFiles
            guard !items.variables.isEmpty else { return }
            if let project, let p = doc.projects.firstIndex(where: { $0.id == project }) {
                for v in items.variables {
                    // Same name: the shared value replaces this one (Recently Deleted isn't needed; History keeps it).
                    if let i = doc.projects[p].variables.firstIndex(where: { $0.name == v.name }) {
                        doc.projects[p].variables[i].values.merge(v.values) { _, new in new }
                    } else {
                        doc.projects[p].variables.append(v)
                    }
                }
            } else {
                doc.projects.insert(Project(name: newProject ?? items.projectName ?? "Shared by \(from)", variables: items.variables), at: 0)
            }
        }
        receiving = nil
    }

    /// A `.slinkyproject` opened or dropped: join it, or (already here) remember where its file is.
    func openSharedProject(_ url: URL) {
        SharedProjects.shared.model = self
        SharedProjects.shared.join(url)
    }

    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        case 2: "\(names[0]) and \(names[1])"
        default: names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
    }
}
