import AppKit
import SwiftUI
import LocalAuthentication
import Observation
import SlinkyCoreShared
import SlinkyCoreVault
import UniformTypeIdentifiers

enum LibraryFilter: String, CaseIterable, Hashable {
    // One per kind of item, like Passwords' Passkeys, Codes and Wi-Fi. Secret files sit with keys.
    case all, keys, codes, recoveryKeys

    var title: String {
        switch self {
        case .all: "All Items"
        case .keys: "Keys & Tokens"
        case .codes: "Recovery Codes"
        case .recoveryKeys: "Recovery Keys"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .keys: "key"
        case .codes: "number"
        case .recoveryKeys: "lifepreserver"
        }
    }
}

enum SidebarItem: Hashable {
    case library(LibraryFilter)
    case attention
    case project(UUID)
    case trash
    case activity
}

enum EditTarget: Hashable {
    case key(UUID), kept(UUID), codes(UUID), project(UUID), file(UUID)
}

/// One row in the library list.
enum LibraryRef: Hashable {
    case key(UUID), codes(UUID), kept(UUID), file(UUID)

    var editTarget: EditTarget {
        switch self {
        case let .key(id): .key(id)
        case let .codes(id): .codes(id)
        case let .kept(id): .kept(id)
        case let .file(id): .file(id)
        }
    }
}

enum LockReason {
    case manual, screenLocked, sleep, idle, timeLimit

    var note: String {
        switch self {
        case .manual: "You locked Slinky."
        case .screenLocked: "Locked when your screen locked."
        case .sleep: "Locked when your Mac went to sleep."
        case .idle: "Locked after \(Preferences.shared.autoLockMinutes) minutes of inactivity."
        case .timeLimit: "Locked after 12 hours."
        }
    }
}

struct RecentItem: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let provider: String?
    let value: String
    var mono: Bool { title.allSatisfy { $0.isUppercase || $0 == "_" || $0.isNumber } }
}

struct Toast: Identifiable, Equatable {
    /// Green checkmarks only for things that worked. Information and removals get quiet icons.
    enum Style: Equatable { case success, info, removed }

    let id = UUID()
    var text: String
    var canUndo = false
    var style: Style = .success
}

/// Owns the vault session and every change to it. Views only read `document` and call these methods.
@Observable
final class AppModel {
    /// One model for the window, the menu bar, Quick Access and Shortcuts.
    static let shared = AppModel()

    enum Phase: Equatable {
        case loading, locked, unlocked
    }

    var phase: Phase = .loading

    /// The full-window lock and unlock transition (see `LockCurtain`). Views animate it; the model only says which way.
    enum Curtain: Equatable { case none, closing, opening }
    var curtain: Curtain = .none
    /// While locking plays, the toolbar is already the locked window's. Unlocking shows the app's own toolbar from
    /// the first frame: the whole window is in place before the keyhole opens, and nothing loads in afterwards.
    var lockedChrome: Bool { curtain == .closing }
    var document = VaultDocument() {
        didSet {
            IconResolver.shared.load(siteIcons: document.siteIcons)
            quickItemsCache = nil   // rebuilt on the next search; also drops values from memory when locking
        }
    }
    /// Quick Access and search items, built once per change of the vault rather than on every keystroke.
    @ObservationIgnored var quickItemsCache: [QuickItem]?
    var selection: SidebarItem? = .library(.all)
    var showTuck = false
    var showNewProject = false
    /// The item open in the Edit panel, if any.
    var editing: EditTarget?
    /// Saved values found outside Slinky (Health). In memory only; cleared on lock.
    var leaks: [LeakFinding] = []
    var checkingLeaks = false
    /// When the last check finished, since this unlock. Findings live in memory only, so after a lock or a
    /// relaunch Health says it hasn't looked yet rather than showing an all-clear it can't back up.
    var leaksChecked: Date?
    /// A key copied in another app that the person chose to save while Slinky was locked. Memory only.
    @ObservationIgnored var pendingSave: String?
    /// The selected library row, so search can jump to an item and the detail pane can follow it.
    var librarySelection: LibraryRef?
    /// Edit should open with Replace already on (rotating a key).
    @ObservationIgnored var editReplacing = false
    /// The item whose icon is being chosen (Choose Icon…).
    var choosingIcon: LibraryRef?
    /// What an import file contained, while the import panel is open.
    var importing: Importer.Result?
    var importSource: URL?
    /// A folder to start New Project with (from a drop on the sidebar).
    var newProjectFolder: URL?
    var tuckPrefill = ""
    var tuckProject: UUID?
    /// Unsaved Add Item work, kept in memory so a stray Esc or click doesn't lose it. Cleared on lock.
    var addDraft: AddItemPanel.Draft?
    var toast: Toast?
    var errorMessage: String?
    var lockNote: String?
    var busy = false
    /// Shown once, right after the vault is created by the first save.
    var recoveryKeyToShow: String?
    var hasVault = false
    var quickAccessToken = UUID()
    /// The last few things copied, for the menu bar. Memory only; cleared on lock.
    var recent: [RecentItem] = []
    @ObservationIgnored var openMainWindow: (() -> Void)?

    @ObservationIgnored private var session: VaultSession?
    #if DEBUG
    /// Debug builds: showing a fake vault (Debug/DemoData.swift). Nothing is saved while it's on.
    @ObservationIgnored var isDemo = false
    #endif
    @ObservationIgnored private let enclave = EnclaveWrapper()
    /// The `slinky` command's line in (Agents/BrokerServer.swift).
    @ObservationIgnored private var broker: BrokerServer?
    /// Approvals a person gave from their own terminal or Xcode, reused for an hour. Never for agents. Cleared on lock.
    @ObservationIgnored var grants: [String: Date] = [:]
    @ObservationIgnored private lazy var store = VaultStore(url: VaultStore.defaultURL, enclave: enclave)
    @ObservationIgnored private var unlockedAt: Date?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var idleTimer: Timer?
    @ObservationIgnored private var undoSnapshot: VaultDocument?

    /// The sidebar search field. Cleared on lock.
    var searchText = ""

    var isUnlocked: Bool { phase == .unlocked }

    func start() {
        guard phase == .loading else { return }
        #if DEBUG
        if let fixture = DemoFixture.fromArguments { startDemo(fixture); return }
        #endif
        hasVault = store.exists
        ClipboardWatcher.shared.start()
        if broker == nil {
            broker = BrokerServer { request, peer in await AppModel.shared.handle(request, peer: peer) }
            broker?.start()
        }
        // No welcome screen: with no vault yet, open straight into the (empty) app.
        phase = hasVault ? .locked : .unlocked
        observeLocks()
    }

    // MARK: Create and unlock

    /// The vault is created the first time something is tucked away, then the Recovery Key is shown in context.
    private func createVaultWithCurrentDocument() {
        do {
            try enclave.ensureKey()
            let (newSession, recovery) = try store.create(document)
            session = newSession
            hasVault = true
            unlockedAt = .now
            recoveryKeyToShow = recovery.display
            startIdleTimer()
        } catch {
            errorMessage = Self.friendly(error)
        }
    }

    /// "Unlock with Touch ID" on Macs that have it, otherwise the password wording.
    var unlockLabel: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .touchID: return "Unlock with Touch ID"
        case .opticID, .faceID: return "Unlock"
        default: return "Unlock with Password"
        }
    }

    func unlock() {
        guard !busy else { return }
        busy = true
        errorMessage = nil
        let store = self.store
        Task {
            // The Secure Enclave step waits for Touch ID, so it runs off the main thread.
            let result: Result<VaultSession, Error> = await Task.detached {
                let ctx = LAContext()
                ctx.localizedReason = "unlock your vault"
                do { return .success(try store.unlock(context: ctx)) } catch { return .failure(error) }
            }.value
            busy = false
            switch result {
            case let .success(newSession): didUnlock(newSession)
            case let .failure(error): errorMessage = Self.friendly(error)
            }
        }
    }

    @discardableResult
    func unlock(recoveryText: String) -> Bool {
        guard let key = RecoveryKey(recoveryText) else {
            errorMessage = "That isn't a valid Recovery Key. It has 8 groups of 4 characters."
            return false
        }
        do {
            try enclave.ensureKey()
            didUnlock(try store.unlock(recovery: key))
            show("Unlocked with your Recovery Key. Touch ID is set up on this Mac again.")
            return true
        } catch {
            errorMessage = Self.friendly(error)
            return false
        }
    }

    private func didUnlock(_ newSession: VaultSession) {
        session = newSession
        document = newSession.document
        IconResolver.shared.saveSiteIcon = { [weak self] domain, png in self?.setSiteIcon(domain, png: png) }
        unlockedAt = .now
        lockNote = nil
        errorMessage = nil
        // Recently Deleted keeps things for 30 days.
        if document.purgeTrash() > 0 { persist() }
        // Look for leaks once a day, quietly, after unlocking.
        if Date.now.timeIntervalSince(Preferences.shared.lastLeakCheck) > 86_400 { Task { await checkForLeaks() } }
        if let value = pendingSave {
            pendingSave = nil
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                openAddItem(prefill: value)
            }
        }
        // Set together with the phase so the curtain is already over the window on the first frame.
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { curtain = .opening }
        Sounds.play(.unlocked)
        phase = .unlocked
        startIdleTimer()
    }

    // MARK: Requests from the slinky command

    /// Unlocks for a request from the `slinky` command: one Touch ID, with the reason saying what's asking for what.
    func unlockForRequest(reason: String) async -> Bool {
        guard hasVault else { return false }
        if isUnlocked { return true }
        let store = self.store
        let result: Result<VaultSession, Error> = await Task.detached {
            let ctx = LAContext()
            ctx.localizedReason = reason
            do { return .success(try store.unlock(context: ctx)) } catch { return .failure(error) }
        }.value
        guard case let .success(session) = result else { return false }
        didUnlock(session)
        return true
    }

    /// Asks the person, with Touch ID (or their password), whether to allow what `reason` describes.
    /// Unlocking for it counts as the yes, so there's never a second prompt.
    func approve(reason: String) async -> Bool {
        if !isUnlocked { return await unlockForRequest(reason: reason) }
        let context = LAContext()
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return true
        } catch {
            return false
        }
    }

    func clearActivity() {
        document.log = []
        persist()
        if selection == .activity { selection = .library(.all) }
    }

    /// Adds a line to Activity. Names only.
    func record(_ entry: ActivityEntry) {
        guard isUnlocked else { return }
        document.log.insert(entry, at: 0)
        persist()
    }

    /// Settings › Recovery Key. Confirms it's you, then returns the new key to show exactly once.
    /// The old printed key stops working; Touch ID on this Mac is unchanged.
    func makeNewRecoveryKey() async -> String? {
        guard let session else { return nil }
        let context = LAContext()
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "make a new Recovery Key")
        } catch {
            return nil
        }
        do {
            return try store.replaceRecoveryKey(for: session).display
        } catch {
            show(Self.friendly(error), style: .info)
            return nil
        }
    }

    // MARK: Backups

    var canExportBackup: Bool { isUnlocked && hasVault && session != nil }
    /// Restoring replaces this Mac's vault, so an existing one must be unlocked first.
    var canRestoreBackup: Bool { !hasVault || isUnlocked }
    var showRestore = false

    /// No declared type (the app has no Info.plist of its own); the extension is enough for the save panel.
    static let backupType = UTType(filenameExtension: "slinkybackup", conformingTo: .data) ?? .data

    /// File › Export Backup…: confirms it's you, then asks where to save. The file is named by date only.
    func exportBackup() async {
        guard canExportBackup, var current = session else { return }
        let context = LAContext()
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "export a backup of your vault")
        } catch { return }
        let panel = NSSavePanel()
        panel.title = "Export Backup"
        panel.nameFieldStringValue = "Slinky Backup \(Date.now.formatted(.iso8601.year().month().day())).slinkybackup"
        panel.allowedContentTypes = [Self.backupType]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        current.document = document
        do {
            try store.exportBackup(for: current, to: url)
            show("Backup saved. It opens with your current Recovery Key.")
        } catch {
            show("Couldn't save the backup: \(Self.friendly(error))", style: .info)
        }
    }

    /// Restore from Backup…: the backup's Recovery Key opens it, then it becomes this Mac's vault.
    /// Returns a plain message if it didn't work.
    func restoreBackup(from url: URL, recoveryText: String) async -> String? {
        guard canRestoreBackup else { return "Unlock Slinky first." }
        guard let key = RecoveryKey(recoveryText) else { return "That isn't a valid Recovery Key. It has 8 groups of 4 characters." }
        guard VaultStore.isVaultFile(url) else { return "That file isn't a Slinky backup." }
        if hasVault {
            let context = LAContext()
            do {
                try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "replace your vault with a backup")
            } catch { return "" }
        }
        do {
            try enclave.ensureKey()
            let restored = try store.restoreBackup(from: url, recovery: key)
            hasVault = true
            // Nothing from the vault it replaced carries over: no Undo into it, no recent copies.
            undoSnapshot = nil
            recent = []
            didUnlock(restored)
            selection = .library(.all)
            librarySelection = nil
            show("Restored from your backup. Touch ID opens it on this Mac now.")
            return nil
        } catch VaultError.wrongRecoveryKey {
            return "That Recovery Key doesn't open this backup. Use the key you had when the backup was made."
        } catch {
            return Self.friendly(error)
        }
    }

    /// Lock from the switch, the menu or ⌃⌘L: frost covers the window first, then the vault locks.
    /// The lock itself never waits on a view, so it happens even with the window closed.
    func lockAnimated() {
        guard phase == .unlocked, hasVault, curtain == .none else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            lock(reason: .manual)
            return
        }
        curtain = .closing
        Sounds.play(.locked)
        Task {
            try? await Task.sleep(for: .milliseconds(620))
            lock(reason: .manual)
        }
    }

    func lock(reason: LockReason) {
        curtain = .none
        guard phase == .unlocked, hasVault else { return }
        session = nil
        document = VaultDocument()
        recent = []
        searchText = ""
        undoSnapshot = nil
        showTuck = false
        showNewProject = false
        editing = nil
        importing = nil
        importSource = nil
        // Prefill can hold a pasted secret (Shortcuts, a drop, ⌘V); it never outlives the unlock.
        tuckPrefill = ""
        tuckProject = nil
        addDraft = nil
        librarySelection = nil
        choosingIcon = nil
        showRestore = false
        grants = [:]
        leaks = []
        leaksChecked = nil
        pendingSave = nil
        // Names and website icons it worked out stay only while unlocked.
        IconResolver.shared.reset()
        idleTimer?.invalidate()
        lockNote = reason.note
        phase = .locked
        // With the animation, the sound started with it (lockAnimated), so its bolt lands as the keyhole closes.
        if reason == .manual, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { Sounds.play(.locked) }
    }

    // MARK: Changes

    private func change(_ toastText: String? = nil, undoable: Bool = false, _ edit: (inout VaultDocument) -> Void) {
        if undoable { undoSnapshot = document }
        edit(&document)
        persist()
        if let toastText { show(toastText, canUndo: undoable) }
    }

    func undo() {
        guard var snapshot = undoSnapshot else { return }
        snapshot.activity = document.activity   // Undo restores items, not history.
        document = snapshot
        undoSnapshot = nil
        persist()
        show("Restored.")
    }

    /// A change people should see happen: a new item sliding into the list, a fixed leak leaving Health.
    /// Just a quick fade with Reduce Motion.
    func animated(_ body: () -> Void) {
        let calm = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(calm ? .easeOut(duration: 0.2) : .smooth(duration: 0.38), body)
    }

    func addKept(_ item: KeptItem) {
        animated { change("Saved to Recovery Keys.") { $0.kept.insert(item, at: 0) } }
        Sounds.play(.saved)
        selection = .library(.recoveryKeys)
    }

    func addKey(_ key: Key) {
        animated { change("Saved to Keys & Tokens.") { $0.keys.insert(key, at: 0) } }
        Sounds.play(.saved)
        selection = .library(.keys)
    }

    func addCodeSet(_ set: CodeSet) {
        animated { change("Saved \(set.codes.count) recovery codes.") { $0.codeSets.insert(set, at: 0) } }
        Sounds.play(.saved)
        selection = .library(.codes)
    }

    @discardableResult
    func createProject(name: String, folder: URL? = nil) -> UUID {
        var project = Project(name: name, folders: folder.map { [$0.path] } ?? [])
        if let folder, let example = try? String(contentsOf: folder.appendingPathComponent(".env.example"), encoding: .utf8) {
            project.expected = DotEnv.names(example)
        }
        change { $0.projects.append(project) }
        selection = .project(project.id)
        return project.id
    }

    /// A dropped folder or .env file opens New Project with that folder already read, so it can be checked first.
    func startProject(dropped url: URL) {
        var isDir: ObjCBool = false
        let isFolder = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        newProjectFolder = isFolder ? url : url.deletingLastPathComponent()
        showTuck = false
        showNewProject = true
    }

    /// Creates a project and imports its variables in one step, with one message.
    @discardableResult
    func createProject(name: String, folder: URL?, expected: [String], imports: [(lines: [DotEnvLine], env: AppEnvironment)]) -> UUID {
        var project = Project(name: name, folders: folder.map { [$0.path] } ?? [])
        project.expected = expected
        for item in imports { Self.merge(item.lines, into: &project, env: item.env) }
        let count = Set(project.variables.map(\.name)).count
        change(count == 0 ? "Created \(name)." : "Created \(name) with \(count) \(count == 1 ? "variable" : "variables").") {
            $0.projects.append(project)
        }
        Sounds.play(count > 1 ? .imported : .saved)
        selection = .project(project.id)
        return project.id
    }

    private static func merge(_ lines: [DotEnvLine], into project: inout Project, env: AppEnvironment) {
        for line in lines {
            if let v = project.variables.firstIndex(where: { $0.name == line.name }) {
                project.variables[v].setValue(line.value, in: env)
            } else {
                project.variables.append(Variable(
                    name: line.name, values: [env: line.value], isPlain: line.isPlain,
                    provider: Detector.detect(line.value)?.provider))
            }
        }
    }

    func addVariables(_ lines: [DotEnvLine], to projectID: UUID, env: AppEnvironment) {
        guard let p = document.projects.firstIndex(where: { $0.id == projectID }) else { return }
        change(lines.count == 1 ? "Saved \(lines[0].name) to \(document.projects[p].name)." : "Imported \(lines.count) variables to \(document.projects[p].name).") { doc in
            Self.merge(lines, into: &doc.projects[p], env: env)
        }
        Sounds.play(lines.count > 1 ? .imported : .saved)
        selection = .project(projectID)
    }

    func importEnvFile(_ url: URL, into projectID: UUID, env: AppEnvironment) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            errorMessage = "Couldn't read \(url.lastPathComponent)."
            return
        }
        if url.lastPathComponent.hasSuffix(".example") {
            change("Read \(url.lastPathComponent). Missing variables are marked.") { doc in
                guard let p = doc.projects.firstIndex(where: { $0.id == projectID }) else { return }
                doc.projects[p].expected = DotEnv.names(text)
            }
            return
        }
        let lines = DotEnv.parse(text)
        guard !lines.isEmpty else {
            errorMessage = "No KEY=value lines in \(url.lastPathComponent)."
            return
        }
        addVariables(lines, to: projectID, env: env)
    }

    func linkFolder(_ url: URL, to projectID: UUID) {
        change("Linked \(url.lastPathComponent).") { doc in
            guard let p = doc.projects.firstIndex(where: { $0.id == projectID }) else { return }
            if !doc.projects[p].folders.contains(url.path) { doc.projects[p].folders.append(url.path) }
            if let example = try? String(contentsOf: url.appendingPathComponent(".env.example"), encoding: .utf8) {
                doc.projects[p].expected = DotEnv.names(example)
            }
        }
    }

    func setPolicy(_ policy: AgentPolicy, variable: UUID, in projectID: UUID) {
        change { doc in
            guard let p = doc.projects.firstIndex(where: { $0.id == projectID }),
                  let v = doc.projects[p].variables.firstIndex(where: { $0.id == variable }) else { return }
            doc.projects[p].variables[v].agentPolicy = policy
        }
    }

    func setValue(_ value: String?, variable: UUID, in projectID: UUID, env: AppEnvironment) {
        change(value == nil ? "Removed from \(env.title)." : "Saved.") { doc in
            guard let p = doc.projects.firstIndex(where: { $0.id == projectID }),
                  let v = doc.projects[p].variables.firstIndex(where: { $0.id == variable }) else { return }
            doc.projects[p].variables[v].setValue(value, in: env)
        }
    }

    /// Opens Add Item. `prefill` is something handed in (a paste, a drop, Shortcuts); `project` aims it at a project.
    /// Every way in goes through here, so nothing from an earlier time can linger.
    /// Add Item, Edit, New Project or Import is open. Only one at a time: opening another over Edit lost its changes.
    var panelOpen: Bool { showTuck || showNewProject || editing != nil || importing != nil }

    func openAddItem(prefill: String = "", project: UUID? = nil) {
        guard isUnlocked else { return }
        // From the menu bar, Quick Access, a shortcut or the clipboard: don't replace something half done.
        guard !showNewProject, editing == nil, importing == nil else {
            show("Finish or cancel what's open first.", style: .info)
            return
        }
        tuckPrefill = prefill
        tuckProject = project
        showTuck = true
    }

    /// A note and link for a variable that was just added from Add Item.
    func setDetails(note: String?, link: String?, variableNamed name: String, in projectID: UUID) {
        guard note != nil || link != nil else { return }
        change { doc in
            guard let p = doc.projects.firstIndex(where: { $0.id == projectID }),
                  let v = doc.projects[p].variables.firstIndex(where: { $0.name == name }) else { return }
            if let note { doc.projects[p].variables[v].note = note }
            if let link { doc.projects[p].variables[v].link = link }
        }
    }

    /// The details pane's note and link fields. Empty clears them; a link that isn't https is dropped.
    func setVariableDetails(note: String, link: String, variable: UUID, in projectID: UUID) {
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = Links.normalized(link)
        guard let p = document.projects.firstIndex(where: { $0.id == projectID }),
              let v = document.projects[p].variables.firstIndex(where: { $0.id == variable }) else { return }
        let current = document.projects[p].variables[v]
        guard current.note ?? "" != note || current.link != link else { return }
        change { doc in
            doc.projects[p].variables[v].note = note.isEmpty ? nil : note
            doc.projects[p].variables[v].link = link
        }
    }

    func deleteVariable(_ variable: UUID, in projectID: UUID) {
        change(Self.trashToast, undoable: true) { doc in
            guard let p = doc.projects.firstIndex(where: { $0.id == projectID }),
                  let v = doc.projects[p].variables.first(where: { $0.id == variable }) else { return }
            doc.projects[p].variables.removeAll { $0.id == variable }
            doc.trashed.insert(TrashEntry(.variable(v, projectID: projectID, projectName: doc.projects[p].name)), at: 0)
        }
    }

    func deleteProject(_ projectID: UUID) {
        change(Self.trashToast, undoable: true) { doc in
            guard let project = doc.projects.first(where: { $0.id == projectID }) else { return }
            doc.projects.removeAll { $0.id == projectID }
            doc.trashed.insert(TrashEntry(.project(project)), at: 0)
        }
        selection = .library(.all)
    }

    // MARK: Edits

    /// nil goes back to automatic.
    func setIcon(_ choice: IconChoice?, for ref: LibraryRef) {
        change { doc in
            switch ref {
            case let .key(id): if let i = doc.keys.firstIndex(where: { $0.id == id }) { doc.keys[i].icon = choice }
            case let .codes(id): if let i = doc.codeSets.firstIndex(where: { $0.id == id }) { doc.codeSets[i].icon = choice }
            case let .kept(id): if let i = doc.kept.firstIndex(where: { $0.id == id }) { doc.kept[i].icon = choice }
            case let .file(id): if let i = doc.secretFiles.firstIndex(where: { $0.id == id }) { doc.secretFiles[i].icon = choice }
            }
        }
    }

    /// Where it lives (a catalog id), or nil to let Slinky work it out.
    func setService(_ id: String?, for ref: LibraryRef) {
        change { doc in
            switch ref {
            case let .key(i): if let n = doc.keys.firstIndex(where: { $0.id == i }) { doc.keys[n].service = id }
            case let .codes(i): if let n = doc.codeSets.firstIndex(where: { $0.id == i }) { doc.codeSets[n].service = id }
            case let .kept(i): if let n = doc.kept.firstIndex(where: { $0.id == i }) { doc.kept[n].service = id }
            case let .file(i): if let n = doc.secretFiles.firstIndex(where: { $0.id == i }) { doc.secretFiles[n].service = id }
            }
        }
    }

    /// A website's icon, fetched by WebsiteIcons, kept inside the vault.
    func setSiteIcon(_ domain: String, png: Data) {
        guard isUnlocked else { return }
        change { doc in
            var icons = doc.siteIcons ?? [:]
            icons[domain] = png
            doc.siteIcons = icons
        }
    }

    func iconSubject(_ ref: LibraryRef) -> IconSubject? {
        switch ref {
        case let .key(id): document.keys.first { $0.id == id }?.iconSubject
        case let .codes(id): document.codeSets.first { $0.id == id }?.iconSubject
        case let .kept(id): document.kept.first { $0.id == id }?.iconSubject
        case let .file(id): document.secretFiles.first { $0.id == id }?.iconSubject
        }
    }

    func update(_ key: Key) {
        guard let i = document.keys.firstIndex(where: { $0.id == key.id }) else { return }
        var key = key
        key.updated = .now
        change("Saved changes to \(key.name).") { $0.keys[i] = key }
    }

    func update(_ item: KeptItem) {
        guard let i = document.kept.firstIndex(where: { $0.id == item.id }) else { return }
        change("Saved changes to \(item.label).") { $0.kept[i] = item }
    }

    func update(_ set: CodeSet) {
        guard let i = document.codeSets.firstIndex(where: { $0.id == set.id }) else { return }
        change("Saved changes to \(set.account).") { $0.codeSets[i] = set }
    }

    func update(_ project: Project) {
        guard let i = document.projects.firstIndex(where: { $0.id == project.id }) else { return }
        change("Saved changes to \(project.name).") { $0.projects[i] = project }
    }

    // Removing never deletes outright: it moves to Recently Deleted for 30 days (and Undo works right away).
    static let trashToast = "Moved to Recently Deleted."

    // MARK: Rotation

    /// Where to make a new one: the service's own key page, else the item's link, else the service's site.
    func rotationURL(for subject: IconSubject) -> URL? {
        let service = IconResolver.shared.service(for: subject)
        if let s = service?.tokenURL, let url = URL(string: s) { return url }
        if let link = subject.link, let url = URL(string: link) { return url }
        if let domain = service?.domains.first { return URL(string: "https://\(domain)") }
        return nil
    }

    /// "Make a New Key on GitHub…": opens the service's key page, and Edit with Replace ready for the new value.
    func startRotation(_ ref: LibraryRef) {
        if let subject = iconSubject(ref), let url = rotationURL(for: subject) { NSWorkspace.shared.open(url) }
        editReplacing = true
        editing = ref.editTarget
    }

    /// A key got a new value: the old one waits in Recently Deleted (in case the new one doesn't work yet),
    /// and project variables that held the old value get the new one too.
    func replaced(_ old: Key, with new: Key) {
        var projectsUpdated: [String] = []
        change { doc in
            var retired = old
            retired.id = UUID()
            retired.name = "\(old.name) (replaced)"
            doc.trashed.insert(TrashEntry(.key(retired)), at: 0)
            for p in doc.projects.indices {
                for v in doc.projects[p].variables.indices {
                    for env in AppEnvironment.allCases where doc.projects[p].variables[v].value(in: env) == old.value {
                        doc.projects[p].variables[v].values[env.rawValue] = new.value
                        doc.projects[p].variables[v].updated = .now
                        projectsUpdated.append("\(doc.projects[p].name) (\(env.title))")
                    }
                }
            }
        }
        record(ActivityEntry(action: .rotated, names: [new.name], detail: projectsUpdated.isEmpty ? "" : "Also updated in " + projectsUpdated.joined(separator: ", ")))
        Sounds.play(.saved)   // a new key is stored, the same as saving one
        show(projectsUpdated.isEmpty ? "Replaced \(new.name). The old one is in Recently Deleted for 30 days."
                                     : "Replaced \(new.name), and in \(projectsUpdated.joined(separator: ", ")). The old one is in Recently Deleted.")
    }

    func deleteFile(_ id: UUID) {
        change(Self.trashToast, undoable: true) { doc in
            guard let file = doc.secretFiles.first(where: { $0.id == id }) else { return }
            doc.secretFiles.removeAll { $0.id == id }
            doc.trashed.insert(TrashEntry(.file(file)), at: 0)
        }
    }

    func update(_ file: SecretFile) {
        guard let i = document.secretFiles.firstIndex(where: { $0.id == file.id }) else { return }
        var file = file
        file.updated = .now
        change("Saved changes to \(file.name).") { $0.secretFiles[i] = file }
    }

    /// A dropped or picked file becomes a secret file in the vault (256 KB at most). App Store Connect keys
    /// get their Key ID from the file name, then Edit opens for the Issuer ID.
    func addFile(_ url: URL) {
        guard isUnlocked else { return }
        guard let data = try? Data(contentsOf: url) else { show("Couldn't read \(url.lastPathComponent).", style: .info); return }
        guard data.count <= SecretFile.maxBytes else {
            show("\(url.lastPathComponent) is too big for a secret (over 256 KB).", style: .info)
            return
        }
        let kind = SecretFile.guessKind(filename: url.lastPathComponent, data: data)
        var fields: [String: String] = [:]
        if kind == .appStoreConnectKey, let id = SecretFile.keyID(fromFilename: url.lastPathComponent) { fields["Key ID"] = id }
        let name = kind == .appStoreConnectKey ? "App Store Connect API key" : (url.deletingPathExtension().lastPathComponent)
        let file = SecretFile(name: name, filename: url.lastPathComponent, kind: kind, data: data, fields: fields)
        animated { change("Saved \(url.lastPathComponent) to Slinky. You can move the original to the Trash.") { $0.secretFiles.insert(file, at: 0) } }
        Sounds.play(.saved)
        selection = .library(.keys)
        librarySelection = .file(file.id)
        if kind == .appStoreConnectKey, file.fields["Issuer ID"] == nil { editing = .file(file.id) }
    }

    func deleteKept(_ id: UUID) {
        change(Self.trashToast, undoable: true) { doc in
            guard let item = doc.kept.first(where: { $0.id == id }) else { return }
            doc.kept.removeAll { $0.id == id }
            doc.trashed.insert(TrashEntry(.kept(item)), at: 0)
        }
    }

    func deleteKey(_ id: UUID) {
        change(Self.trashToast, undoable: true) { doc in
            guard let key = doc.keys.first(where: { $0.id == id }) else { return }
            doc.keys.removeAll { $0.id == id }
            doc.trashed.insert(TrashEntry(.key(key)), at: 0)
        }
    }

    func deleteCodeSet(_ id: UUID) {
        change(Self.trashToast, undoable: true) { doc in
            guard let set = doc.codeSets.first(where: { $0.id == id }) else { return }
            doc.codeSets.removeAll { $0.id == id }
            doc.trashed.insert(TrashEntry(.codes(set)), at: 0)
        }
    }

    // MARK: Recently Deleted

    /// Puts something back where it was. A variable whose project is gone comes back in a project of that name.
    func restore(_ entryID: UUID) {
        guard let entry = document.trashed.first(where: { $0.id == entryID }) else { return }
        change("Restored \(entry.item.title).") { doc in
            doc.trashed.removeAll { $0.id == entryID }
            switch entry.item {
            case .key(let k): doc.keys.insert(k, at: 0)
            case .codes(let c): doc.codeSets.insert(c, at: 0)
            case .kept(let k): doc.kept.insert(k, at: 0)
            case .file(let f): doc.secretFiles.insert(f, at: 0)
            case .project(let p):
                var p = p
                if doc.projects.contains(where: { $0.id == p.id }) { p.id = UUID() }
                doc.projects.append(p)
            case .variable(let v, let projectID, let projectName):
                if let i = doc.projects.firstIndex(where: { $0.id == projectID }) {
                    doc.projects[i].variables.removeAll { $0.name == v.name && $0.id == v.id }
                    doc.projects[i].variables.append(v)
                } else {
                    doc.projects.append(Project(name: projectName, variables: [v]))
                }
            }
        }
        if document.trashed.isEmpty, selection == .trash { selection = .library(.all) }
    }

    /// Gone for good. The person confirms this in the view.
    func deleteNow(_ entryID: UUID) {
        change("Deleted.") { $0.trashed.removeAll { $0.id == entryID } }
        if document.trashed.isEmpty, selection == .trash { selection = .library(.all) }
    }

    func emptyTrash() {
        change("Recently Deleted is empty.") { $0.trashed = [] }
        if selection == .trash { selection = .library(.all) }
    }

    /// Copies one recovery code and crosses it off.
    func useCode(_ index: Int, in setID: UUID) {
        guard let s = document.codeSets.firstIndex(where: { $0.id == setID }),
              document.codeSets[s].codes.indices.contains(index),
              !document.codeSets[s].used.contains(index) else { return }
        Clipboard.copy(document.codeSets[s].codes[index], clearAfter: Double(Preferences.shared.clipboardSeconds))
        Preferences.shared.copyCount += 1
        record(ActivityEntry(action: .codeUsed, names: ["\(document.codeSets[s].account) recovery code"]))
        change(undoable: true) { $0.codeSets[s].used.insert(index) }
        let left = document.codeSets[s].remaining
        if left <= 3 { Reminders.codesLow(account: document.codeSets[s].account, left: left) }
        show("Copied and marked as used. \(left) left." + (left <= 3 ? " Consider generating new codes." : ""), canUndo: true, style: .success)
    }

    // MARK: Duplicates and import

    /// Everywhere this exact value is already saved, in plain words ("Keys & Tokens, as GITHUB_TOKEN").
    /// Compared in memory only, while unlocked. Nothing about the value is stored for this.
    func places(of raw: String) -> [String] {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return [] }
        var out: [String] = []
        for key in document.keys where key.value == value { out.append("Keys & Tokens, as \(key.name)") }
        for item in document.kept where item.value == value { out.append("Recovery, as \(item.label)") }
        for set in document.codeSets where set.codes.contains(value) { out.append("Recovery, in \(set.account) codes") }
        for project in document.projects {
            for variable in project.variables {
                let envs = AppEnvironment.allCases.filter { variable.value(in: $0) == value }
                if !envs.isEmpty { out.append("\(project.name), as \(variable.name) (\(envs.map(\.title).joined(separator: ", ")))") }
            }
        }
        return out
    }

    /// The same check for a set of codes: any overlap with a saved set.
    func places(ofCodes codes: [String]) -> [String] {
        let wanted = Set(codes)
        return document.codeSets.filter { !wanted.isDisjoint(with: $0.codes) }.map { "Recovery, in \($0.account) codes" }
    }

    /// Saves what the person picked on the import screen, in one change with one message.
    func importItems(_ items: [Importer.Candidate]) {
        guard !items.isEmpty else { return }
        animated { change("Imported \(items.count) \(items.count == 1 ? "item" : "items").") { doc in
            for item in items {
                switch item.kind {
                case let .key(provider, isLive, expires):
                    doc.keys.append(Key(name: item.name, value: item.value, provider: provider, isLive: isLive,
                                        expires: expires, note: item.note))
                case let .codes(codes):
                    doc.codeSets.append(CodeSet(account: item.name, codes: codes))
                case let .recoveryKey(kind):
                    doc.kept.append(KeptItem(label: item.name, kind: kind, value: item.value, note: item.note))
                }
            }
        } }
        Sounds.play(.imported)
        selection = .library(.all)
    }

    func markPrinted(_ id: UUID) {
        change { doc in
            guard let i = doc.kept.firstIndex(where: { $0.id == id }) else { return }
            doc.kept[i].printedCopy = true
        }
    }

    func copy(_ value: String, label: String, provider: String? = nil, remember: Bool = true) {
        Clipboard.copy(value, clearAfter: Double(Preferences.shared.clipboardSeconds))
        Preferences.shared.copyCount += 1
        record(ActivityEntry(action: .copied, names: [label]))
        if remember {
            recent.removeAll { $0.title == label }
            recent.insert(RecentItem(title: label, provider: provider, value: value), at: 0)
            recent = Array(recent.prefix(3))
        }
        show("Copied \(label). \(Self.clipboardNote)")
    }

    /// "The clipboard clears in 60 seconds." with the current setting.
    static var clipboardNote: String { "The clipboard clears in \(Preferences.clipboardDuration(Preferences.shared.clipboardSeconds))." }

    func show(_ text: String, canUndo: Bool = false, style: Toast.Style? = nil) {
        // Undoable toasts are removals.
        let t = Toast(text: text, canUndo: canUndo, style: style ?? (canUndo ? .removed : .success))
        toast = t
        Task {
            try? await Task.sleep(for: .seconds(canUndo ? 5 : 2.6))
            if toast?.id == t.id { toast = nil }
        }
    }

    func persist() {
        #if DEBUG
        if isDemo { return }   // a fake vault is never written anywhere
        #endif
        guard var current = session else {
            if !hasVault { createVaultWithCurrentDocument() }
            return
        }
        current.document = document
        session = current
        do { try store.save(current) } catch { errorMessage = "Couldn't save: \(Self.friendly(error))" }
        Reminders.schedule(document)
    }

    // MARK: Locking

    private func observeLocks() {
        let dnc = DistributedNotificationCenter.default()
        observers.append(dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if Preferences.shared.lockOnScreenLock { self?.lock(reason: .screenLocked) } }
        })
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if Preferences.shared.lockOnSleep { self?.lock(reason: .sleep) } }
            })
        }
    }

    private func startIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.phase == .unlocked else { return }
                let anyInput = CGEventType(rawValue: UInt32.max)!
                if CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput) > Double(Preferences.shared.autoLockMinutes * 60) {
                    self.lock(reason: .idle)
                } else if let at = self.unlockedAt, Date.now.timeIntervalSince(at) > 12 * 3600 {
                    self.lock(reason: .timeLimit)
                }
            }
        }
    }

    static func friendly(_ error: Error) -> String {
        if let la = error as? LAError {
            switch la.code {
            case .userCancel, .appCancel, .systemCancel: return "Unlock was cancelled."
            case .authenticationFailed: return "Touch ID didn't recognize you. Try again."
            default: return la.localizedDescription
            }
        }
        if let vault = error as? VaultError { return vault.description }
        let ns = error as NSError
        if ns.domain == "CryptoTokenKit" || ns.code == -2 { return "Unlock was cancelled." }
        return error.localizedDescription
    }
}

extension AppModel {
    /// Demo mode skips Quick Access's hotkey and the update check, so it can run beside the real app.
    var isDemoMode: Bool {
        #if DEBUG
        isDemo
        #else
        false
        #endif
    }

    #if DEBUG
    /// Shows a fake vault, unlocked, without touching the real vault, Touch ID, the socket or the clipboard.
    func startDemo(_ fixture: DemoFixture) {
        isDemo = true
        hasVault = false
        document = fixture.document()
        leaks = fixture.leaks()
        leaksChecked = .now
        selection = .library(.all)
        librarySelection = nil
        editing = nil
        showTuck = false
        phase = .unlocked
    }
    #endif
}
