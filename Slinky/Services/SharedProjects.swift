import AppKit
import LocalAuthentication
import SlinkyCoreShared
import SlinkyCoreVault

/// Shared projects: one encrypted `.slinkyproject` file per project, in a folder the team already syncs (a shared
/// iCloud Drive folder, Dropbox, a NAS). Like VaultSync, Slinky makes no network request: it reads and writes the
/// file, and the team's sync service moves it. Every copy is checked (signed by a member; only a member can change
/// who's in it; never older than one already seen) and merged variable by variable.
@MainActor
@Observable
final class SharedProjects {
    static let shared = SharedProjects()

    @ObservationIgnored weak var model: AppModel?
    /// Per project: something to tell the person, in plain words. nil when all is well.
    private(set) var problems: [UUID: String] = [:]
    private(set) var lastSynced: [UUID: Date] = [:]
    /// Projects whose key changed (someone was removed) and need Touch ID to read the new one.
    private(set) var needsNewKey: Set<UUID> = []
    /// Projects this Mac was removed from: the copy stays, and stops updating.
    private(set) var removed: Set<UUID> = []
    /// After removing someone: the secrets they could see, to replace. Names only.
    var checklist: RotationChecklist?

    @ObservationIgnored private var watchers: [UUID: FileWatcher] = [:]
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    /// What each project looked like when last read or written (values, in memory only, cleared on lock), so a save
    /// that didn't touch a shared project doesn't rewrite its file.
    @ObservationIgnored private var lastShared: [UUID: Project] = [:]

    private init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in SharedProjects.shared.pullAll() }
        }
    }

    // MARK: Folders (paths, per Mac; never values)

    private static let foldersKey = "sharedProjectFolders"

    func folder(for projectID: UUID) -> URL? {
        (UserDefaults.standard.dictionary(forKey: Self.foldersKey)?[projectID.uuidString] as? String)
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private func setFolder(_ folder: URL?, for projectID: UUID) {
        var all = UserDefaults.standard.dictionary(forKey: Self.foldersKey) ?? [:]
        all[projectID.uuidString] = folder?.path
        UserDefaults.standard.set(all, forKey: Self.foldersKey)
    }

    func fileURL(for project: Project) -> URL? {
        guard let sharing = project.sharing else { return nil }
        return folder(for: project.id)?.appendingPathComponent(sharing.fileName)
    }

    private var sharedProjects: [Project] { model?.document.projects.filter { $0.sharing != nil } ?? [] }

    // MARK: Lifecycle

    func unlocked(_ model: AppModel) {
        self.model = model
        guard !model.isDemoMode else { return }
        for project in sharedProjects { watch(project) }
        pullAll()
    }

    func locked() {
        pushTask?.cancel()
        watchers.values.forEach { $0.stop() }
        watchers = [:]
        lastShared = [:]
        needsNewKey = []
        removed = []
        checklist = nil
    }

    /// After every save on this Mac, a moment later.
    func saved() {
        guard model?.isUnlocked == true, !sharedProjects.isEmpty else { return }
        pushTask?.cancel()
        pushTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            for project in sharedProjects where Self.content(project) != lastShared[project.id].map(Self.content) { push(project.id) }
        }
    }

    /// The part of a project that's shared: everything but this Mac's folders.
    private static func content(_ project: Project) -> Project {
        var p = project
        p.folders = []
        p.sharing?.seen = nil
        return p
    }

    // MARK: Reading

    func pullAll() {
        for project in sharedProjects { pull(project.id) }
    }

    func pull(_ projectID: UUID) {
        guard let model, model.isUnlocked, !model.isDemoMode,
              let project = model.document.projects.first(where: { $0.id == projectID }), let sharing = project.sharing,
              let url = fileURL(for: project) else { return }
        for copy in CoordinatedFile.conflictedCopies(of: url) { mergeConflicted(copy, into: projectID) }
        guard let data = CoordinatedFile.read(url, presenter: watchers[projectID]) else {
            problems[projectID] = "The shared file isn't in the folder. If someone moved it, choose the folder again."
            return
        }
        do {
            let file = try SharedProjectFile.read(data)
            guard file.project == projectID else { throw SharingError.badFile("it's a different project") }
            try file.check(against: sharing)
            var key = sharing.key
            if file.epoch != sharing.epoch {
                // Removed: the new key wasn't sealed to this Mac. Say so without asking for Touch ID first.
                if let card = model.myCard, !file.isFor(card) {
                    removed.insert(projectID)
                    stopWatching(projectID)
                } else {
                    needsNewKey.insert(projectID)
                }
                return
            }
            defer { key.resetBytes(in: 0..<key.count) }
            apply(file, key: key, to: projectID)
        } catch let problem as SharedProjectFile.Problem where problem == .older {
            // A slow sync handed back an older copy: put ours back.
            push(projectID)
        } catch {
            problems[projectID] = AppModel.friendly(error)
        }
    }

    /// Touch ID, then the new key after someone was removed.
    func takeNewKey(_ projectID: UUID) async {
        guard let model, let project = model.document.projects.first(where: { $0.id == projectID }), let sharing = project.sharing,
              let url = fileURL(for: project), let data = CoordinatedFile.read(url, presenter: watchers[projectID]),
              let card = model.myCard else { return }
        do {
            let file = try SharedProjectFile.read(data)
            try file.check(against: sharing)
            let reason = "open the new key for \(project.name)"
            let key = try await Task.detached {
                let context = LAContext()
                context.localizedReason = reason
                return try file.openKey(me: card, keys: AppModel.sharingKeys, context: context)
            }.value
            needsNewKey.remove(projectID)
            apply(file, key: key, to: projectID)
        } catch let problem as SharedProjectFile.Problem where problem == .notForThisMac {
            needsNewKey.remove(projectID)
            removed.insert(projectID)
            stopWatching(projectID)
        } catch {
            problems[projectID] = AppModel.friendly(error)
        }
    }

    private func apply(_ file: SharedProjectFile, key: Data, to projectID: UUID) {
        guard let model, let i = model.document.projects.firstIndex(where: { $0.id == projectID }),
              let fileName = model.document.projects[i].sharing?.fileName else { return }
        do {
            let remote = try file.project(key: key, myName: myMemberName(in: file.members))
            let local = model.document.projects[i]
            var merged = VaultMerge.mergeProject(local, remote)
            merged.folders = local.folders
            merged.sharing = file.sharing(key: key, fileName: fileName)
            if merged != local {
                var doc = model.document
                doc.projects[i] = merged
                model.applySynced(doc)
            }
            lastShared[projectID] = remote
            problems[projectID] = nil
            lastSynced[projectID] = .now
            // This Mac had changes the copy didn't: write them back.
            if Self.content(merged) != Self.content(remote) { push(projectID) }
        } catch {
            problems[projectID] = AppModel.friendly(error)
        }
    }

    private func mergeConflicted(_ url: URL, into projectID: UUID) {
        guard let model, let sharing = model.document.projects.first(where: { $0.id == projectID })?.sharing,
              let data = CoordinatedFile.read(url, presenter: nil), let file = try? SharedProjectFile.read(data),
              file.project == projectID, file.epoch == sharing.epoch, (try? file.check(against: nil)) != nil,
              sharing.member(for: file.savedBy) != nil else { return }
        apply(file, key: sharing.key, to: projectID)
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    // MARK: Writing

    func push(_ projectID: UUID, membersChanged: Date? = nil) {
        guard let model, model.isUnlocked, !model.isDemoMode,
              let project = model.document.projects.first(where: { $0.id == projectID }), let sharing = project.sharing,
              let url = fileURL(for: project), let card = model.myCard else { return }
        guard sharing.member(for: card) != nil else {
            problems[projectID] = "This Mac isn't in the project yet. Send your card to a member and ask them to add this Mac."
            return
        }
        let previous = CoordinatedFile.read(url, presenter: watchers[projectID]).flatMap { try? SharedProjectFile.read($0) }
        do {
            let data = try SharedProjectFile.write(project, sharing: sharing, me: card, keys: AppModel.sharingKeys,
                                                   membersChanged: membersChanged, previous: previous)
            try CoordinatedFile.write(data, to: url, presenter: watchers[projectID])
            lastShared[projectID] = project
            problems[projectID] = nil
            lastSynced[projectID] = .now
        } catch {
            problems[projectID] = "Couldn't write to the shared folder. Check that it's still there and that Slinky can use it."
        }
    }

    // MARK: Starting, joining, members

    /// Everyone on the list, as they are in People. You go first, with every Mac of yours.
    private func members(_ personIDs: Set<UUID>) -> [SharedMember] {
        guard let model, let me = model.document.me else { return [] }
        let others = model.document.people.filter { personIDs.contains($0.id) && !$0.isMe }
        return [SharedMember(name: me.name, cards: me.cards)] + others.map { SharedMember(name: $0.name, cards: $0.cards) }
    }

    private func myMemberName(in members: [SharedMember]) -> String? {
        guard let card = model?.myCard else { return nil }
        return members.first { $0.has(card) }?.name
    }

    /// Project › Share › Share Project with Team…: choose people and a folder the team syncs.
    func start(_ projectID: UUID, with personIDs: Set<UUID>, in folder: URL) async -> Bool {
        guard let model = model ?? Optional(AppModel.shared), let project = model.document.projects.first(where: { $0.id == projectID }) else { return false }
        self.model = model
        guard let card = model.myCard else {
            model.show("This Mac couldn't make its sharing card, so it can't share yet.", style: .info)
            return false
        }
        let people = members(personIDs)
        guard people.count > 1 else {
            model.show("Pick at least one person to share \(project.name) with.", style: .info)
            return false
        }
        guard await model.approve(reason: "share \(project.name) with \(AppModel.list(people.dropFirst().map(\.name)))") else { return false }
        let fileName = Self.fileName(for: project, in: folder)
        do {
            let (data, sharing) = try SharedProjectFile.start(project, members: people, me: card, keys: AppModel.sharingKeys, fileName: fileName)
            setFolder(folder, for: projectID)
            try CoordinatedFile.write(data, to: folder.appendingPathComponent(fileName), presenter: nil)
            model.change("Shared \(project.name). Changes now go to the team folder.",
                         activity: ActivityEntry(action: .members, names: [project.name], detail: AppModel.list(people.map(\.name)))) { doc in
                guard let i = doc.projects.firstIndex(where: { $0.id == projectID }) else { return }
                doc.projects[i].sharing = sharing
            }
            if let shared = model.document.projects.first(where: { $0.id == projectID }) {
                lastShared[projectID] = shared
                watch(shared)
            }
            lastSynced[projectID] = .now
            return true
        } catch {
            model.show("Couldn't share \(project.name): \(AppModel.friendly(error))", style: .info)
            setFolder(nil, for: projectID)
            return false
        }
    }

    /// A `.slinkyproject` opened or found: who it's from, then Touch ID, then it joins this vault.
    func join(_ url: URL) {
        guard let model, !model.isDemoMode else { return }
        guard let data = CoordinatedFile.read(url, presenter: nil), let file = try? SharedProjectFile.read(data) else {
            model.show("That isn't a shared Slinky project, or it's damaged.", style: .info)
            return
        }
        // Already here (this Mac, or another of yours through sync): just remember where the file is.
        if let existing = model.document.projects.first(where: { $0.id == file.project }), existing.sharing != nil {
            setFolder(url.deletingLastPathComponent(), for: file.project)
            watch(existing)
            pull(file.project)
            model.selection = .project(file.project)
            return
        }
        guard let card = model.myCard, file.isFor(card) else {
            model.show("This project isn't shared with this Mac. Send your card to \(file.membersSignedBy.name) and ask them to add you.", style: .info)
            return
        }
        do { try file.check(against: nil) } catch {
            model.show(AppModel.friendly(error), style: .info)
            return
        }
        let from = model.document.person(for: file.membersSignedBy)
        let sender = from?.name ?? file.membersSignedBy.name
        Task {
            // Open first (Touch ID), so the question can say which project and what's in it.
            let project: Project
            let key: Data
            do {
                key = try await Task.detached {
                    let context = LAContext()
                    context.localizedReason = "open what \(sender) shared"
                    return try file.openKey(me: card, keys: AppModel.sharingKeys, context: context)
                }.value
                project = try file.project(key: key, myName: file.members.first { $0.has(card) }?.name)
            } catch {
                model.show(AppModel.friendly(error), style: .info)
                return
            }
            let others = file.members.filter { !$0.has(card) }.map(\.name)
            let alert = NSAlert()
            alert.messageText = "\(sender) shared \(project.name) with you"
            alert.informativeText = (from?.checked == true ? "" : "Slinky doesn't know this card, or you haven't compared its code. Check with \(sender) before you use these values.\n\n")
                + "\(counted(project.variables.count, "variable")), shared with \(AppModel.list(others)). Changes anyone makes reach everyone through this folder."
            alert.addButton(withTitle: "Add \(project.name)")
            alert.addButton(withTitle: "Not Now")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            var added = project
            added.sharing = file.sharing(key: key, fileName: url.lastPathComponent)
            setFolder(url.deletingLastPathComponent(), for: added.id)
            model.change("Added \(added.name), shared by \(sender).") { $0.projects.insert(added, at: 0) }
            lastShared[added.id] = added
            watch(added)
            model.selection = .project(added.id)
        }
    }

    func addPeople(_ personIDs: Set<UUID>, to projectID: UUID) async {
        guard let model, let project = model.document.projects.first(where: { $0.id == projectID }), var sharing = project.sharing else { return }
        let added = members(personIDs).dropFirst()
        guard !added.isEmpty, await model.approve(reason: "add \(AppModel.list(added.map(\.name))) to \(project.name)") else { return }
        for member in added { sharing = sharing.adding(member) }
        changeMembers(projectID, to: sharing, detail: "added \(AppModel.list(added.map(\.name)))")
    }

    /// Someone already in the project has a new Mac (its card is in People): it can open the project too.
    func addNewMacs(of member: SharedMember, in projectID: UUID) async {
        guard let model, let project = model.document.projects.first(where: { $0.id == projectID }), let sharing = project.sharing,
              let person = model.document.people.first(where: { p in member.cards.contains(where: { p.has($0) }) }) else { return }
        guard await model.approve(reason: "let \(person.name)'s other Mac open \(project.name)") else { return }
        changeMembers(projectID, to: sharing.adding(SharedMember(name: member.name, cards: person.cards)), detail: "added \(person.name)'s other Mac")
    }

    /// A new key sealed only to who's left, then the list of secrets they could see.
    func remove(_ member: SharedMember, from projectID: UUID) async {
        guard let model, let project = model.document.projects.first(where: { $0.id == projectID }), let sharing = project.sharing else { return }
        guard await model.approve(reason: "remove \(member.name) from \(project.name)") else { return }
        changeMembers(projectID, to: sharing.removing(member), detail: "removed \(member.name)")
        let secrets = project.variables.filter { !$0.isPlain }
        if !secrets.isEmpty { checklist = RotationChecklist(projectID: projectID, person: member.name, variables: secrets.map(\.id)) }
    }

    private func changeMembers(_ projectID: UUID, to sharing: ProjectSharing, detail: String) {
        guard let model, let name = model.document.projects.first(where: { $0.id == projectID })?.name else { return }
        model.change(activity: ActivityEntry(action: .members, names: [name], detail: detail)) { doc in
            guard let i = doc.projects.firstIndex(where: { $0.id == projectID }) else { return }
            doc.projects[i].sharing = sharing
        }
        push(projectID, membersChanged: .now)
    }

    /// This Mac stops following the shared file. The project stays here as an ordinary one; others keep theirs.
    func stopSharing(_ projectID: UUID) {
        guard let model else { return }
        stopWatching(projectID)
        setFolder(nil, for: projectID)
        problems[projectID] = nil
        needsNewKey.remove(projectID)
        removed.remove(projectID)
        model.change("This Mac stopped following the shared project. Your copy stays here.") { doc in
            guard let i = doc.projects.firstIndex(where: { $0.id == projectID }) else { return }
            doc.projects[i].sharing = nil
        }
    }

    /// "harvous.slinkyproject", or "harvous 2.slinkyproject" if that name is taken by another project.
    private static func fileName(for project: Project, in folder: URL) -> String {
        let base = project.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        var name = "\(base).\(SharedProjectFile.fileExtension)"
        var n = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
            name = "\(base) \(n).\(SharedProjectFile.fileExtension)"
            n += 1
        }
        return name
    }

    // MARK: Watching

    private func watch(_ project: Project) {
        guard let url = fileURL(for: project), watchers[project.id] == nil else { return }
        let id = project.id
        watchers[id] = FileWatcher(url: url) { Task { @MainActor in SharedProjects.shared.pull(id) } }
    }

    private func stopWatching(_ projectID: UUID) {
        watchers[projectID]?.stop()
        watchers[projectID] = nil
    }
}

/// After someone leaves a shared project: the secrets they could see, to replace one by one. Names only.
struct RotationChecklist: Identifiable, Equatable {
    let id = UUID()
    let projectID: UUID
    let person: String
    let variables: [UUID]
}

/// Tells Slinky when a sync service changes one file.
nonisolated final class FileWatcher: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue.main
    private let changed: @Sendable () -> Void

    init(url: URL, changed: @escaping @Sendable () -> Void) {
        presentedItemURL = url
        self.changed = changed
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    func presentedItemDidChange() { changed() }

    func stop() { NSFileCoordinator.removeFilePresenter(self) }
}
