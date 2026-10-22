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

extension VaultDocument {
    /// Whether the item a library row points at is still here.
    func contains(_ ref: LibraryRef) -> Bool {
        switch ref {
        case let .key(id): keys.contains { $0.id == id }
        case let .codes(id): codeSets.contains { $0.id == id }
        case let .kept(id): kept.contains { $0.id == id }
        case let .file(id): secretFiles.contains { $0.id == id }
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
    /// A variable to select when its project shows (from search, Activity): its id and environment.
    var revealVariable: (id: UUID?, env: AppEnvironment)?

    /// The folder review (New Project, Update from Folder), while it's open.
    var review: FolderReview?
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
    /// The one change that can be taken back (a delete, an import), until anything else changes. Memory only.
    @ObservationIgnored private var undoStep: UndoStep?
    /// The main window's undo manager, so Edit › Undo names the step and ⌘Z takes it back.
    @ObservationIgnored weak var windowUndoManager: UndoManager?

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
        // Catch up with the sync folder, if there is one.
        VaultSync.shared.unlocked(self)
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
            // Backups made before now open only with the old key: Health asks for a new one.
            Preferences.shared.newKeySinceBackup = true
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
            Preferences.shared.lastBackup = Calendar.current.startOfDay(for: .now)
            Preferences.shared.newKeySinceBackup = false
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
            setUndo(nil)
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
        VaultSync.shared.locked()
        setUndo(nil)
        // A message from while it was open would otherwise sit on the lock screen and hold up Touch ID.
        errorMessage = nil
        showTuck = false
        review = nil
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

    /// What a change does to Undo. Most changes clear it, so Undo never reaches back past them.
    enum UndoRule {
        case clears
        /// Doesn't touch what Undo would restore (a website icon arriving).
        case keeps
        /// Can be taken back: `name` is what Edit › Undo says ("Undo Delete"), `undone` the toast afterwards.
        case records(name: String, undone: String = "Restored.")
    }

    private struct UndoStep {
        let name: String
        let undone: String
        let before: VaultDocument
        let activityID: UUID?
    }

    /// Every edit to the vault goes through here: the edit, an optional Activity entry, Undo, the save and a toast.
    /// Returns false if the save failed (already said in a toast).
    @discardableResult
    func change(_ toastText: String? = nil, undo rule: UndoRule = .clears, activity: ActivityEntry? = nil,
                toastStyle: Toast.Style? = nil, _ edit: (inout VaultDocument) -> Void) -> Bool {
        let before = document
        edit(&document)
        // What changed carries today's date, so syncing knows it's the newer version.
        document.stampChanges(since: before)
        if let activity { document.log.insert(activity, at: 0) }
        var undoable = false
        switch rule {
        case .clears: setUndo(nil)
        case .keeps: break
        case let .records(name, undone):
            setUndo(UndoStep(name: name, undone: undone, before: before, activityID: activity?.id))
            undoable = true
        }
        let saved = persist()
        if let toastText, saved { show(toastText, canUndo: undoable, style: toastStyle) }
        return saved
    }

    private func setUndo(_ step: UndoStep?) {
        undoStep = step
        guard let manager = windowUndoManager, !manager.isUndoing else { return }
        manager.removeAllActions(withTarget: self)
        guard let step else { return }
        manager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.undo() }
        }
        manager.setActionName(step.name)
    }

    var canUndo: Bool { undoStep != nil }

    func undo() {
        guard let step = undoStep else { return }
        guard !panelOpen else {
            show("Finish or cancel what's open first.", style: .info)
            // ⌘Z used up the menu's step; put it back once this undo has finished.
            DispatchQueue.main.async { self.setUndo(step) }
            return
        }
        var restored = step.before
        // Undo restores items, not history, and keeps website icons that arrived since.
        restored.siteIcons = document.siteIcons
        restored.log = document.log.filter { $0.id != step.activityID }
        // Taking something back is a change of its own: dated now, so a synced copy doesn't bring it back.
        restored.removed = document.removed
        restored.stampChanges(since: document)
        document = restored
        undoStep = nil
        if let manager = windowUndoManager, !manager.isUndoing { manager.removeAllActions(withTarget: self) }
        // Don't leave the window on something that's gone again.
        if case let .project(id)? = selection, !document.projects.contains(where: { $0.id == id }) { selection = .library(.all) }
        if let ref = librarySelection, !document.contains(ref) { librarySelection = nil }
        persist()
        show(step.undone)
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

    enum ProjectChoice { case existing(UUID), new(String) }

    /// Variables from Add Item, into an existing project or a new one, as one change Undo takes back. Values
    /// already there are replaced (Add Item says so first); nothing else in the project changes.
    func addVariables(_ lines: [DotEnvLine], to choice: ProjectChoice, env: AppEnvironment,
                      note: String? = nil, link: String? = nil) {
        let isNew: Bool
        var project: Project
        switch choice {
        case let .existing(id):
            guard let p = document.projects.first(where: { $0.id == id }) else { return }
            project = p
            isNew = false
        case let .new(name):
            project = Project(name: name)
            isNew = true
        }
        let changes = FolderChanges.compare(project, with: [FolderChanges.Source(id: "Add Item", environment: env, lines: lines, precedence: 0)])
        let picks = FolderChanges.Picks(rows: Set(changes.changes.filter { [.new, .changed].contains($0.status()) }.map(\.id)))
        let summary = changes.summary(for: picks)
        changes.apply(picks, to: &project)
        if lines.count == 1, let i = project.variables.firstIndex(where: { $0.name == lines[0].name }) {
            if let note { project.variables[i].note = note }
            if let link { project.variables[i].link = link }
        }
        let text = lines.count == 1 ? "Saved \(lines[0].name) to \(project.name)." : "Saved to \(project.name): \(summary.text)."
        let saved = change(text, undo: .records(name: isNew ? "New Project" : "Add Variables", undone: "Took that back."),
                           toastStyle: .success) { doc in
            if isNew {
                doc.projects.append(project)
            } else if let i = doc.projects.firstIndex(where: { $0.id == project.id }) {
                doc.projects[i] = project
            }
        }
        guard saved else { return }
        Sounds.play(lines.count > 1 ? .imported : .saved)
        selection = .project(project.id)
    }

    /// How many of these names already have a different value in the project's environment (Add Item says so).
    func replacing(_ lines: [DotEnvLine], in projectID: UUID, env: AppEnvironment) -> Int {
        guard let project = document.projects.first(where: { $0.id == projectID }) else { return 0 }
        return lines.filter { line in project.variables.first { $0.name == line.name }?.value(in: env).map { $0 != line.value } ?? false }.count
    }

    func importEnvFile(_ url: URL, into projectID: UUID, env: AppEnvironment) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            show("Couldn't read \(url.lastPathComponent).", style: .info)
            return
        }
        if ProjectScan.isSkipped(url.lastPathComponent) {
            show("\(url.lastPathComponent) holds keys for another tool, not variables. Slinky leaves it alone.", style: .info)
            return
        }
        // .env.example, .sample, .template, .dist: names only, added to what the project expects.
        if ProjectScan.isExample(url.lastPathComponent) {
            change("Read \(url.lastPathComponent). Missing variables are marked.", undo: .records(name: "Read Example File")) { doc in
                guard let p = doc.projects.firstIndex(where: { $0.id == projectID }) else { return }
                var seen = Set(doc.projects[p].expected)
                doc.projects[p].expected += DotEnv.names(text).filter { seen.insert($0).inserted }
            }
            return
        }
        guard !DotEnv.parse(text).isEmpty else {
            show("No KEY=value lines in \(url.lastPathComponent).", style: .info)
            return
        }
        review = FolderReview(target: .project(projectID), file: url, environmentHint: env)
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

    /// Add Item, Edit, New Project or Import is open. Only one at a time: opening another over Edit lost its changes.
    var panelOpen: Bool { showTuck || review != nil || editing != nil || importing != nil }

    /// Opens Add Item. `prefill` is something handed in (a paste, a drop, Shortcuts); `project` aims it at a project.
    /// Every way in goes through here, so nothing from an earlier time can linger.
    func openAddItem(prefill: String = "", project: UUID? = nil) {
        guard isUnlocked else { return }
        // From the menu bar, Quick Access, a shortcut or the clipboard: don't replace something half done.
        guard review == nil, editing == nil, importing == nil else {
            show("Finish or cancel what's open first.", style: .info)
            return
        }
        tuckPrefill = prefill
        tuckProject = project
        showTuck = true
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

    /// Renames a variable. Names follow .env rules, and two variables in a project can't share one.
    /// Returns a plain reason when it can't.
    @discardableResult
    func renameVariable(_ variable: UUID, in projectID: UUID, to newName: String) -> String? {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard name.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
            return "Use letters, numbers and underscores, starting with a letter, like RESEND_API_KEY."
        }
        guard let p = document.projects.firstIndex(where: { $0.id == projectID }) else { return nil }
        guard !document.projects[p].variables.contains(where: { $0.name == name && $0.id != variable }) else {
            return "\(document.projects[p].name) already has \(name)."
        }
        change("Renamed to \(name).", undo: .records(name: "Rename")) { doc in
            guard let v = doc.projects[p].variables.firstIndex(where: { $0.id == variable }) else { return }
            doc.projects[p].variables[v].name = name
            doc.projects[p].variables[v].updated = .now
        }
        return nil
    }

    /// Public settings ship to the browser anyway; secrets never do. Switches which one a variable is.
    func setPlain(_ plain: Bool, variable: UUID, in projectID: UUID) {
        change(plain ? "Moved to Public settings." : "Moved to Secrets.") { doc in
            guard let p = doc.projects.firstIndex(where: { $0.id == projectID }),
                  let v = doc.projects[p].variables.firstIndex(where: { $0.id == variable }) else { return }
            doc.projects[p].variables[v].isPlain = plain
        }
    }

    /// Copies (or moves) a variable to another project. If that project already has the name, only environments
    /// it doesn't have a value for are filled in.
    func copyVariable(_ variable: UUID, from projectID: UUID, to targetID: UUID, move: Bool) {
        guard let source = document.projects.first(where: { $0.id == projectID }),
              let v = source.variables.first(where: { $0.id == variable }),
              let target = document.projects.first(where: { $0.id == targetID }) else { return }
        change("\(move ? "Moved" : "Copied") \(v.name) to \(target.name).", undo: .records(name: move ? "Move" : "Copy to Project")) { doc in
            guard let t = doc.projects.firstIndex(where: { $0.id == targetID }) else { return }
            if let existing = doc.projects[t].variables.firstIndex(where: { $0.name == v.name }) {
                for env in AppEnvironment.allCases where doc.projects[t].variables[existing].value(in: env) == nil {
                    if let value = v.value(in: env) { doc.projects[t].variables[existing].setValue(value, in: env) }
                }
            } else {
                var copy = v
                copy.id = UUID()
                copy.updated = .now
                doc.projects[t].variables.append(copy)
            }
            if move, let s = doc.projects.firstIndex(where: { $0.id == projectID }) {
                doc.projects[s].variables.removeAll { $0.id == variable }
            }
        }
    }

    func deleteVariable(_ variable: UUID, in projectID: UUID) {
        change(Self.trashToast, undo: .records(name: "Delete")) { doc in
            guard let p = doc.projects.firstIndex(where: { $0.id == projectID }),
                  let v = doc.projects[p].variables.first(where: { $0.id == variable }) else { return }
            doc.projects[p].variables.removeAll { $0.id == variable }
            doc.trashed.insert(TrashEntry(.variable(v, projectID: projectID, projectName: doc.projects[p].name)), at: 0)
        }
    }

    func deleteProject(_ projectID: UUID) {
        change(Self.trashToast, undo: .records(name: "Delete")) { doc in
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
        change(undo: .keeps) { doc in
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
        change(Self.trashToast, undo: .records(name: "Delete")) { doc in
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
        change(Self.trashToast, undo: .records(name: "Delete")) { doc in
            guard let item = doc.kept.first(where: { $0.id == id }) else { return }
            doc.kept.removeAll { $0.id == id }
            doc.trashed.insert(TrashEntry(.kept(item)), at: 0)
        }
    }

    func deleteKey(_ id: UUID) {
        change(Self.trashToast, undo: .records(name: "Delete")) { doc in
            guard let key = doc.keys.first(where: { $0.id == id }) else { return }
            doc.keys.removeAll { $0.id == id }
            doc.trashed.insert(TrashEntry(.key(key)), at: 0)
        }
    }

    func deleteCodeSet(_ id: UUID) {
        change(Self.trashToast, undo: .records(name: "Delete")) { doc in
            guard let set = doc.codeSets.first(where: { $0.id == id }) else { return }
            doc.codeSets.removeAll { $0.id == id }
            doc.trashed.insert(TrashEntry(.codes(set)), at: 0)
        }
    }

    // MARK: Several at once

    /// Several library items to Recently Deleted as one change, so one Undo puts them all back.
    func deleteItems(_ refs: [LibraryRef]) {
        guard !refs.isEmpty else { return }
        change("Moved \(counted(refs.count, "item")) to Recently Deleted.", undo: .records(name: "Delete")) { doc in
            for ref in refs {
                switch ref {
                case let .key(id):
                    if let k = doc.keys.first(where: { $0.id == id }) { doc.keys.removeAll { $0.id == id }; doc.trashed.insert(TrashEntry(.key(k)), at: 0) }
                case let .codes(id):
                    if let c = doc.codeSets.first(where: { $0.id == id }) { doc.codeSets.removeAll { $0.id == id }; doc.trashed.insert(TrashEntry(.codes(c)), at: 0) }
                case let .kept(id):
                    if let k = doc.kept.first(where: { $0.id == id }) { doc.kept.removeAll { $0.id == id }; doc.trashed.insert(TrashEntry(.kept(k)), at: 0) }
                case let .file(id):
                    if let f = doc.secretFiles.first(where: { $0.id == id }) { doc.secretFiles.removeAll { $0.id == id }; doc.trashed.insert(TrashEntry(.file(f)), at: 0) }
                }
            }
        }
        librarySelection = nil
    }

    /// Who may use these keys: AI agents, or only you.
    func setPolicy(_ policy: AgentPolicy, keys ids: Set<UUID>) {
        change("Updated \(counted(ids.count, "key")).") { doc in
            for i in doc.keys.indices where ids.contains(doc.keys[i].id) { doc.keys[i].agentPolicy = policy }
        }
    }

    func setPolicy(_ policy: AgentPolicy, variables ids: Set<UUID>, in projectID: UUID) {
        change("Updated \(counted(ids.count, "variable")).") { doc in
            guard let p = doc.projects.firstIndex(where: { $0.id == projectID }) else { return }
            for i in doc.projects[p].variables.indices where ids.contains(doc.projects[p].variables[i].id) {
                doc.projects[p].variables[i].agentPolicy = policy
            }
        }
    }

    func setPlain(_ plain: Bool, variables ids: Set<UUID>, in projectID: UUID) {
        change(plain ? "Moved \(counted(ids.count, "variable")) to Public settings." : "Moved \(counted(ids.count, "variable")) to Secrets.") { doc in
            guard let p = doc.projects.firstIndex(where: { $0.id == projectID }) else { return }
            for i in doc.projects[p].variables.indices where ids.contains(doc.projects[p].variables[i].id) {
                doc.projects[p].variables[i].isPlain = plain
            }
        }
    }

    /// Several variables to Recently Deleted as one change.
    func deleteVariables(_ ids: Set<UUID>, in projectID: UUID) {
        change("Moved \(counted(ids.count, "variable")) to Recently Deleted.", undo: .records(name: "Delete")) { doc in
            guard let p = doc.projects.firstIndex(where: { $0.id == projectID }) else { return }
            for v in doc.projects[p].variables where ids.contains(v.id) {
                doc.trashed.insert(TrashEntry(.variable(v, projectID: projectID, projectName: doc.projects[p].name)), at: 0)
            }
            doc.projects[p].variables.removeAll { ids.contains($0.id) }
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
        change(undo: .records(name: "Mark as Used")) { $0.codeSets[s].used.insert(index) }
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
    /// Saves what was picked in the import panel as one change that Undo takes back, with a summary and an
    /// Activity entry (names only). Returns whether it saved.
    @discardableResult
    func importItems(_ items: [Importer.Candidate], unchanged: Int = 0, skipped: Int = 0, from file: String? = nil) -> Bool {
        guard !items.isEmpty else { return false }
        let summary = FolderChanges.Summary(new: items.count, unchanged: unchanged, skipped: skipped)
        let entry = ActivityEntry(action: .imported, names: items.map(\.name), detail: file.map { "from \($0)" } ?? "")
        var saved = false
        animated { saved = change("Imported: \(summary.text).", undo: .records(name: "Import", undone: "Took back the import."),
                                  activity: entry, toastStyle: .success) { doc in
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
        guard saved else { return false }
        Sounds.play(.imported)
        selection = .library(.all)
        return true
    }

    /// A code crossed off by mistake goes back on the list.
    func markUnused(_ index: Int, in setID: UUID) {
        change("Marked as unused.") { doc in
            guard let s = doc.codeSets.firstIndex(where: { $0.id == setID }) else { return }
            doc.codeSets[s].used.remove(index)
        }
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

    /// Shows the item an Activity line is about: a key, recovery key, code set, file, or a project's variable.
    /// Returns false when it's gone (or was renamed before item ids were recorded).
    @discardableResult
    func reveal(_ entry: ActivityEntry) -> Bool {
        let ids = Set(entry.itemIDs ?? [])
        let names = Set(entry.names.map { $0.replacingOccurrences(of: " recovery code", with: "") })
        if let key = document.keys.first(where: { ids.contains($0.id) || names.contains($0.name) }) {
            selection = .library(.keys); librarySelection = .key(key.id); return true
        }
        if let set = document.codeSets.first(where: { ids.contains($0.id) || names.contains($0.account) }) {
            selection = .library(.codes); librarySelection = .codes(set.id); return true
        }
        if let item = document.kept.first(where: { ids.contains($0.id) || names.contains($0.label) }) {
            selection = .library(.recoveryKeys); librarySelection = .kept(item.id); return true
        }
        if let file = document.secretFiles.first(where: { ids.contains($0.id) || names.contains($0.name) }) {
            selection = .library(.keys); librarySelection = .file(file.id); return true
        }
        for project in document.projects {
            if let v = project.variables.first(where: { ids.contains($0.id) || names.contains($0.name) }) {
                selection = .project(project.id)
                revealVariable = (v.id, AppEnvironment.allCases.first { v.value(in: $0) != nil } ?? .local)
                return true
            }
        }
        return false
    }

    /// A name with no value (for `process.env.NAME` in code). Still through Clipboard, like every copy, but not
    /// recorded as using anything.
    func copyName(_ name: String) {
        Clipboard.copy(name, clearAfter: Double(Preferences.shared.clipboardSeconds))
        show("Copied the name \(name). No value.")
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

    /// Writes the vault. A failure is said in a toast while unlocked (the lock screen's message would go unseen
    /// and later block Touch ID). Returns whether it saved.
    @discardableResult
    func persist() -> Bool {
        #if DEBUG
        if isDemo { return true }   // a fake vault is never written anywhere
        #endif
        guard var current = session else {
            if !hasVault { createVaultWithCurrentDocument() }
            return true
        }
        current.document = document
        session = current
        do {
            try store.save(current)
        } catch {
            let message = "Couldn't save: \(Self.friendly(error))"
            if isUnlocked { show(message, style: .info) } else { errorMessage = message }
            return false
        }
        Reminders.schedule(document)
        VaultSync.shared.saved()
        return true
    }

    // MARK: Sync (the crypto stays in the vault; VaultSync moves files)

    /// The sync copy of the vault as it is now.
    func syncCopyData() throws -> Data {
        guard var current = session else { throw VaultError.notFound }
        current.document = document
        return try store.syncCopy(for: current)
    }

    /// The document in a sync copy, if it's this vault (nil for a different one).
    func openSyncCopy(_ data: Data) throws -> VaultDocument? {
        guard let session else { throw VaultError.notFound }
        return try store.openSyncCopy(data, session: session)
    }

    func takeNewerRecoveryKey(from data: Data) {
        _ = try? store.takeNewerRecoveryKey(from: data)
    }

    /// A merge with another Mac's copy: saved as it is (no new dates, which would make it look newer than it is).
    func applySynced(_ merged: VaultDocument) {
        guard var current = session else { return }
        current.document = merged
        session = current
        document = merged
        do { try store.save(current) } catch { show("Couldn't save the synced changes: \(Self.friendly(error))", style: .info) }
        Reminders.schedule(document)
    }

    /// Settings › Sync, when the folder holds a different vault: make that vault this Mac's, with its Recovery
    /// Key, folding this Mac's items in. Returns a plain message if it didn't work.
    func adoptSyncedVault(at url: URL, recoveryText: String) async -> String? {
        guard let key = RecoveryKey(recoveryText) else { return "That isn't a valid Recovery Key. It has 8 groups of 4 characters." }
        guard let data = try? Data(contentsOf: url) else { return "Couldn't read the vault in that folder." }
        if hasVault {
            let context = LAContext()
            do {
                try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "use the vault in your sync folder on this Mac")
            } catch { return "" }
        }
        do {
            try enclave.ensureKey()
            let adopted = try store.adopt(syncCopy: data, recovery: key, merging: isUnlocked ? document : nil)
            hasVault = true
            setUndo(nil)
            recent = []
            didUnlock(adopted)
            VaultSync.shared.adopted(folder: url.deletingLastPathComponent().deletingLastPathComponent())
            show("This Mac uses the synced vault now. Its Recovery Key opens everything; this Mac's old one no longer does.")
            return nil
        } catch VaultError.wrongRecoveryKey {
            return "That Recovery Key doesn't open the vault in this folder. Use the key from the Mac that made it."
        } catch {
            return Self.friendly(error)
        }
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
