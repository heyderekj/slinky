import AppKit
import SlinkyCoreShared

/// Health: leaks, things that need a person, and tidying up.
extension AppModel {
    /// `manual`: started with Check Now (an all-clear result then gets its quiet sound), not the daily check.
    func checkForLeaks(manual: Bool = false) async {
        guard isUnlocked, !checkingLeaks else { return }
        #if DEBUG
        // Demo mode never reads the disk: it pretends to look for a moment and keeps the demo's findings.
        if isDemo {
            checkingLeaks = true
            try? await Task.sleep(for: .seconds(1.4))
            checkingLeaks = false
            leaksChecked = .now
            if manual, leaks.isEmpty, attention.isEmpty { Sounds.play(.clear) }
            return
        }
        #endif
        checkingLeaks = true
        let before = Set(leaks.map(\.id))
        let projects = document.projects.map { LeakFinder.ProjectRef(id: $0.id, name: $0.name, folders: $0.folders) }
        let found = await LeakFinder.scan(secrets: scanSecrets(), projects: projects)
        checkingLeaks = false
        guard isUnlocked else { return }   // Locked while looking: forget it.
        leaks = found
        leaksChecked = .now
        Preferences.shared.lastLeakCheck = .now
        let fresh = found.filter { !before.contains($0.id) }
        for f in fresh { record(ActivityEntry(action: .leakFound, names: f.names, actor: "Health", detail: f.title)) }
        if !fresh.isEmpty { Reminders.leaksFound(fresh.flatMap(\.names)) }
        // Asked, and everything's as it should be: the coil settles. Never for the quiet daily check.
        if manual, found.isEmpty, attention.isEmpty { Sounds.play(.clear) }
    }

    /// The value behind a finding's names (to clean history). Stays in memory.
    private func values(for names: [String]) -> [String] {
        let secrets = scanSecrets()
        return secrets.filter { names.contains($0.name) }.map(\.value)
    }

    /// A .env in a linked project opens the folder review for that one file, with "then move it to the Trash" on:
    /// nothing is overwritten without a look first, and the file moves only after the variables are saved.
    func moveIntoSlinky(_ finding: LeakFinding) {
        guard case let .envFile(path, projectID) = finding.place, let projectID else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.isReadableFile(atPath: url.path) else { show("Couldn't read \(url.lastPathComponent).", style: .info); return }
        guard !panelOpen else { show("Finish or cancel what's open first.", style: .info); return }
        review = FolderReview(target: .project(projectID), file: url, trashAfter: url)
    }

    func cleanHistory(_ finding: LeakFinding) {
        guard case let .history(path) = finding.place else { return }
        do {
            let removed = try LeakFinder.cleanHistory(at: path, values: values(for: finding.names))
            animated { leaks.removeAll { $0.id == finding.id } }
            show("Removed \(removed) \(removed == 1 ? "line" : "lines") from \((path as NSString).lastPathComponent). Open terminals keep their own copy until they close.")
        } catch {
            show("Couldn't change \((path as NSString).lastPathComponent).", style: .info)
        }
    }

    /// Keys added over 60 days ago that Activity has never seen copied or used.
    var unusedKeys: [Key] {
        // Importing a key isn't using it.
        let used = Set(document.log.filter { $0.action != .imported }.flatMap(\.names))
        let cutoff = Date.now.addingTimeInterval(-60 * 86_400)
        return document.keys.filter { $0.created < cutoff && !used.contains($0.name) }
    }

    /// Values saved more than once (in different places), by the names they're saved under.
    var duplicates: [[String]] {
        var byValue: [String: [String]] = [:]
        for s in scanSecrets() { byValue[s.value, default: []].append(s.name) }
        return byValue.values.filter { Set($0).count > 1 }.map { Array(Set($0)).sorted() }.sorted { $0[0] < $1[0] }
    }

    /// Everything Health shows a number for.
    var healthCount: Int { attention.count + leaks.count }
}
