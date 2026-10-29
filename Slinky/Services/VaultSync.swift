import AppKit
import SlinkyCoreShared
import SlinkyCoreVault

/// Sync through a folder the person chooses (iCloud Drive, Dropbox, a network drive). Slinky keeps an encrypted
/// copy of the vault there, `Slinky/vault.slinky`, the same file as a backup, and the sync service moves it.
/// Slinky itself makes no network requests. Every Mac that's set up (with the Recovery Key, once) reads the copy,
/// merges item by item, and writes it back. Reads and writes go through NSFileCoordinator, so a sync service
/// never sees half a file.
@MainActor
@Observable
final class VaultSync: NSObject, NSFilePresenter {
    static let shared = VaultSync()

    @ObservationIgnored weak var model: AppModel?
    private(set) var lastSynced: Date?
    /// Something to tell the person (in Settings and Health), in plain words. nil when all is well.
    private(set) var problem: String?
    /// The chosen folder holds a different vault: it needs that vault's Recovery Key (Settings asks).
    private(set) var foreignCopy: URL?

    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var presenting = false
    @ObservationIgnored nonisolated(unsafe) private var watchedURL: URL?

    /// The folder's path. A path, not a value, so it's fine in UserDefaults.
    var folder: URL? {
        UserDefaults.standard.string(forKey: "syncFolder").map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
    var isOn: Bool { folder != nil }
    var copyURL: URL? { folder?.appendingPathComponent("Slinky/vault.slinky") }

    /// "iCloud Drive", "Dropbox", or the folder's name, for "Synced 2 min ago · iCloud Drive".
    var serviceName: String? {
        guard let path = folder?.path else { return nil }
        if path.contains("/Library/Mobile Documents/") { return "iCloud Drive" }
        if path.contains("/Library/CloudStorage/") {
            let part = path.components(separatedBy: "/Library/CloudStorage/")[1].components(separatedBy: "/")[0]
            return part.components(separatedBy: "-").first ?? part
        }
        return folder?.lastPathComponent
    }

    override private init() {
        super.init()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in VaultSync.shared.pull() }
        }
    }

    // MARK: Turning it on and off

    /// Uses `folder` from now on. If it already holds this vault, they merge; if it holds another vault,
    /// `foreignCopy` is set and Settings asks for that vault's Recovery Key; if it's empty, the copy is written.
    func choose(_ chosen: URL) {
        guard let model, model.isUnlocked, !model.isDemoMode else { return }
        let url = chosen.appendingPathComponent("Slinky/vault.slinky")
        if let data = read(url), (try? model.openSyncCopy(data)) == nil {
            foreignCopy = url
            return
        }
        UserDefaults.standard.set(chosen.path, forKey: "syncFolder")
        foreignCopy = nil
        startWatching()
        pull(thenPush: true)
    }

    func stop() {
        UserDefaults.standard.removeObject(forKey: "syncFolder")
        stopWatching()
        lastSynced = nil
        problem = nil
        foreignCopy = nil
    }

    func cancelForeign() { foreignCopy = nil }

    /// A Mac with no vault yet: the vault in this folder is offered (its Recovery Key opens it).
    func offerForeign(_ url: URL) { foreignCopy = url }

    /// After the other vault was adopted: sync with it from now on.
    func adopted(folder: URL) {
        UserDefaults.standard.set(folder.path, forKey: "syncFolder")
        foreignCopy = nil
        startWatching()
        push(now: true)
    }

    // MARK: Lifecycle

    func unlocked(_ model: AppModel) {
        self.model = model
        // A demo vault never goes near a real sync folder.
        guard isOn, !model.isDemoMode else { return }
        startWatching()
        pull(thenPush: true)
    }

    func locked() {
        pushTask?.cancel()
        stopWatching()
    }

    /// After every save on this Mac, a moment later (a burst of edits goes out once).
    func saved() {
        guard isOn, model?.isUnlocked == true else { return }
        push(now: false)
    }

    // MARK: Reading and writing

    /// Reads the copy, merges it in, and (when asked, or when this Mac has something the copy doesn't) writes it back.
    func pull(thenPush: Bool = false) {
        guard isOn, let model, model.isUnlocked, !model.isDemoMode, let url = copyURL else { return }
        mergeConflictedCopies()
        // No copy yet (just turned on, or it was removed): write one.
        guard let data = read(url) else { push(now: true); return }
        do {
            guard let remote = try model.openSyncCopy(data) else {
                problem = "The sync folder holds a different vault. Choose the folder again in Settings to use it."
                return
            }
            model.takeNewerRecoveryKey(from: data)
            let merged = VaultMerge.merge(model.document, remote)
            if merged != model.document { model.applySynced(merged) }
            problem = nil
            lastSynced = .now
            if thenPush || merged != remote { push(now: true) }
        } catch {
            problem = "Couldn't read the vault in the sync folder."
        }
    }

    private func push(now: Bool) {
        pushTask?.cancel()
        pushTask = Task { @MainActor in
            if !now { try? await Task.sleep(for: .seconds(1.5)) }
            guard !Task.isCancelled else { return }
            writeCopy()
        }
    }

    private func writeCopy() {
        guard isOn, let model, model.isUnlocked, !model.isDemoMode, let url = copyURL else { return }
        // Someone else may have written since the last read: fold that in first, so nothing is lost.
        if let data = read(url), let remote = try? model.openSyncCopy(data) {
            let merged = VaultMerge.merge(model.document, remote)
            if merged != model.document { model.applySynced(merged) }
            if merged == remote { problem = nil; lastSynced = .now; return }
        }
        do {
            let data = try model.syncCopyData()
            try write(data, to: url)
            problem = nil
            lastSynced = .now
        } catch {
            problem = "Couldn't write to the sync folder. Check that it's still there and that Slinky can use it."
        }
    }

    private func read(_ url: URL) -> Data? { CoordinatedFile.read(url, presenter: self) }

    private func write(_ data: Data, to url: URL) throws { try CoordinatedFile.write(data, to: url, presenter: self) }

    /// Dropbox and iCloud keep both versions when two Macs write at once ("vault (conflicted copy).slinky",
    /// "vault 2.slinky"). Ones that open with this vault's key are merged in, then moved to the Trash.
    private func mergeConflictedCopies() {
        guard let model, let dir = copyURL?.deletingLastPathComponent(),
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        for name in names where name.hasSuffix(".slinky") && name != "vault.slinky" && name.hasPrefix("vault") {
            let url = dir.appendingPathComponent(name)
            guard let data = read(url), let other = try? model.openSyncCopy(data) else { continue }
            let merged = VaultMerge.merge(model.document, other)
            if merged != model.document { model.applySynced(merged) }
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    }

    // MARK: Watching

    nonisolated var presentedItemURL: URL? { watchedURL }
    nonisolated var presentedItemOperationQueue: OperationQueue { .main }

    nonisolated func presentedItemDidChange() {
        Task { @MainActor in VaultSync.shared.pull() }
    }

    private func startWatching() {
        watchedURL = copyURL
        guard !presenting else { return }
        NSFileCoordinator.addFilePresenter(self)
        presenting = true
    }

    private func stopWatching() {
        guard presenting else { return }
        NSFileCoordinator.removeFilePresenter(self)
        presenting = false
    }
}
