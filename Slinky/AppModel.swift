import AppKit
import LocalAuthentication
import Observation
import SlinkyCoreShared
import SlinkyCoreVault

enum LibraryFilter: String, CaseIterable, Hashable {
    case all, keys, recovery

    var title: String {
        switch self {
        case .all: "All Items"
        case .keys: "Keys & Tokens"
        case .recovery: "Recovery"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .keys: "key"
        case .recovery: "lifepreserver"
        }
    }
}

enum SidebarItem: Hashable {
    case library(LibraryFilter)
    case attention
    case project(UUID)
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
    var document = VaultDocument()
    var selection: SidebarItem? = .library(.all)
    var showTuck = false
    var showNewProject = false
    /// A folder to start New Project with (from a drop on the sidebar).
    var newProjectFolder: URL?
    var tuckPrefill = ""
    var tuckProject: UUID?
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
    @ObservationIgnored private let enclave = EnclaveWrapper()
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
        hasVault = store.exists
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
        unlockedAt = .now
        lockNote = nil
        errorMessage = nil
        // Set together with the phase so the curtain is already over the window on the first frame.
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { curtain = .opening }
        phase = .unlocked
        startIdleTimer()
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

    /// Lock from the switch, the menu or ⌃⌘L: frost covers the window first, then the vault locks.
    /// The lock itself never waits on a view, so it happens even with the window closed.
    func lockAnimated() {
        guard phase == .unlocked, hasVault, curtain == .none else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            lock(reason: .manual)
            return
        }
        curtain = .closing
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
        idleTimer?.invalidate()
        lockNote = reason.note
        phase = .locked
        if reason == .manual { Sounds.play(.locked) }
    }

    // MARK: Changes

    private func change(_ toastText: String? = nil, undoable: Bool = false, _ edit: (inout VaultDocument) -> Void) {
        if undoable { undoSnapshot = document }
        edit(&document)
        persist()
        if let toastText { show(toastText, canUndo: undoable) }
    }

    func undo() {
        guard let snapshot = undoSnapshot else { return }
        document = snapshot
        undoSnapshot = nil
        persist()
        show("Restored.")
    }

    func addKept(_ item: KeptItem) {
        change("Saved to Recovery.") { $0.kept.insert(item, at: 0) }
        Sounds.play(.saved)
        selection = .library(.recovery)
    }

    func addKey(_ key: Key) {
        change("Saved to Keys & Tokens.") { $0.keys.insert(key, at: 0) }
        Sounds.play(.saved)
        selection = .library(.keys)
    }

    func addCodeSet(_ set: CodeSet) {
        change("Saved \(set.codes.count) recovery codes.") { $0.codeSets.insert(set, at: 0) }
        Sounds.play(.saved)
        selection = .library(.recovery)
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

    func deleteVariable(_ variable: UUID, in projectID: UUID) {
        change("Removed.", undoable: true) { doc in
            guard let p = doc.projects.firstIndex(where: { $0.id == projectID }) else { return }
            doc.projects[p].variables.removeAll { $0.id == variable }
        }
    }

    func deleteProject(_ projectID: UUID) {
        change("Project deleted.", undoable: true) { $0.projects.removeAll { $0.id == projectID } }
        selection = .library(.all)
    }

    func deleteKept(_ id: UUID) { change("Removed.", undoable: true) { $0.kept.removeAll { $0.id == id } } }
    func deleteKey(_ id: UUID) { change("Removed.", undoable: true) { $0.keys.removeAll { $0.id == id } } }
    func deleteCodeSet(_ id: UUID) { change("Removed.", undoable: true) { $0.codeSets.removeAll { $0.id == id } } }

    /// Copies one recovery code and crosses it off.
    func useCode(_ index: Int, in setID: UUID) {
        guard let s = document.codeSets.firstIndex(where: { $0.id == setID }),
              document.codeSets[s].codes.indices.contains(index),
              !document.codeSets[s].used.contains(index) else { return }
        Clipboard.copy(document.codeSets[s].codes[index], clearAfter: Double(Preferences.shared.clipboardSeconds))
        Preferences.shared.copyCount += 1
        change(undoable: true) { $0.codeSets[s].used.insert(index) }
        let left = document.codeSets[s].remaining
        show("Copied and marked as used. \(left) left." + (left <= 3 ? " Consider generating new codes." : ""), canUndo: true, style: .success)
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
        if remember {
            recent.removeAll { $0.title == label }
            recent.insert(RecentItem(title: label, provider: provider, value: value), at: 0)
            recent = Array(recent.prefix(3))
        }
        show("Copied \(label). \(Self.clipboardNote)")
    }

    /// "The clipboard clears in 60 seconds." with the current setting.
    static var clipboardNote: String { "The clipboard clears in \(Preferences.shared.clipboardSeconds) seconds." }

    func show(_ text: String, canUndo: Bool = false, style: Toast.Style? = nil) {
        // Undoable toasts are removals.
        let t = Toast(text: text, canUndo: canUndo, style: style ?? (canUndo ? .removed : .success))
        toast = t
        Task {
            try? await Task.sleep(for: .seconds(canUndo ? 5 : 2.6))
            if toast?.id == t.id { toast = nil }
        }
    }

    private func persist() {
        guard var current = session else {
            if !hasVault { createVaultWithCurrentDocument() }
            return
        }
        current.document = document
        session = current
        do { try store.save(current) } catch { errorMessage = "Couldn't save: \(Self.friendly(error))" }
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
