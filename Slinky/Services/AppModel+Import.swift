import AppKit
import SlinkyCoreShared
import SlinkyCoreVault
import SwiftUI

/// What the folder review is reading and for which project. The review itself (and every value it reads)
/// lives in the panel's state, in memory, until it closes.
struct FolderReview: Identifiable, Equatable {
    enum Target: Equatable { case newProject, project(UUID) }

    let id = UUID()
    var target: Target
    /// Folders to read; they're linked to the project when the review is applied.
    var folders: [URL] = []
    /// One .env file instead of whole folders (a drop, Import .env File…, Health).
    var file: URL?
    /// Already read (demo vaults and snapshots).
    var scans: [ProjectScan]?
    /// Health › Move into Slinky: offer to move this file to the Trash afterwards.
    var trashAfter: URL?
    /// For a single file whose name doesn't say its environment (`.env`): the tab it was dropped on.
    var environmentHint: AppEnvironment?
}

/// Where something was dropped (or picked), which decides what it opens.
enum DropPlace {
    case window
    case projects
    case project(UUID, environment: AppEnvironment? = nil)
}

extension AppModel {
    // MARK: Routing

    /// Every file and folder that comes in, dropped or picked, goes through here:
    /// - an export (.1pux, .csv, .txt) opens Import, wherever it's dropped;
    /// - a folder or a .env file opens the folder review: New Project, or an update to the project it belongs to;
    /// - a .env.example adds its names to what the project expects;
    /// - a key file (.p8, .pem, service-account JSON) is saved to Keys & Tokens.
    func open(_ urls: [URL], on place: DropPlace) {
        guard isUnlocked, !urls.isEmpty else { return }
        guard !panelOpen else { show("Finish or cancel what's open first.", style: .info); return }
        let fm = FileManager.default
        func isFolder(_ url: URL) -> Bool {
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
        let folders = urls.filter(isFolder)
        var files = urls.filter { !isFolder($0) }
        // Sharing: a card adds a person, a share opens for review, a shared project joins.
        if let share = files.first(where: { $0.pathExtension.lowercased() == ShareFile.fileExtension }) { openShare(share); return }
        if let project = files.first(where: { $0.pathExtension.lowercased() == SharedProjectFile.fileExtension }) { openSharedProject(project); return }
        let cards = files.filter { $0.pathExtension.lowercased() == "slinkycard" }
        if !cards.isEmpty { cards.forEach(openCard); files.removeAll { cards.contains($0) }; if files.isEmpty && folders.isEmpty { return } }
        let envFiles = files.filter { ProjectScan.isEnvFile($0.lastPathComponent) }
        let exports = files.filter { !ProjectScan.isEnvFile($0.lastPathComponent) && ["1pux", "csv", "txt"].contains($0.pathExtension.lowercased()) }
        let keyFiles = files.filter { !envFiles.contains($0) && !exports.contains($0) }

        if let export = exports.first { openImport(export); return }

        switch place {
        case let .project(id, environment):
            if let folder = folders.first {
                review = FolderReview(target: .project(id), folders: [folder])
            } else if let file = envFiles.first {
                if ProjectScan.isExample(file.lastPathComponent) || ProjectScan.isSkipped(file.lastPathComponent) {
                    importEnvFile(file, into: id, env: environment ?? .local)
                } else {
                    review = FolderReview(target: .project(id), file: file, environmentHint: environment)
                }
            } else {
                keyFiles.forEach(addFile)
            }
        case .window, .projects:
            if let folder = folders.first {
                review = linkedProject(for: folder).map { FolderReview(target: .project($0), folders: [folder]) }
                    ?? FolderReview(target: .newProject, folders: [folder])
            } else if let file = envFiles.first {
                let folder = file.deletingLastPathComponent()
                review = linkedProject(for: folder).map { FolderReview(target: .project($0), file: file) }
                    ?? FolderReview(target: .newProject, folders: [folder])
            } else {
                keyFiles.forEach(addFile)
            }
        }
    }

    /// The project a folder is already linked to, if any.
    func linkedProject(for folder: URL) -> UUID? {
        let path = folder.standardizedFileURL.path
        return document.projects.first { $0.folders.contains { URL(fileURLWithPath: $0).standardizedFileURL.path == path } }?.id
    }

    /// The URLs in a drop. Waits for every one, so a drop of several files is read once, together.
    static func urls(from providers: [NSItemProvider]) async -> [URL] {
        var out: [URL] = []
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
            }
            if let url { out.append(url) }
        }
        return out
    }

    /// Update from Folder…: reads every folder the project is linked to, or asks for one.
    func updateFromFolder(_ projectID: UUID) {
        guard let project = document.projects.first(where: { $0.id == projectID }) else { return }
        let folders = project.folders.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        if folders.isEmpty {
            chooseFolder(for: projectID)
        } else {
            review = FolderReview(target: .project(projectID), folders: folders)
        }
    }

    /// Link Folder…: pick a folder, then review what it would change.
    func chooseFolder(for projectID: UUID) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Link"
        panel.message = "Choose the project's folder. Slinky reads its .env files and shows what would change. It never changes them."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        review = FolderReview(target: .project(projectID), folders: [url])
    }

    // MARK: Applying

    /// Saves what was picked in the folder review as one change Undo takes back: the project (new or updated),
    /// the key files, and an Activity entry (names only). Files in the folder change only after it's saved,
    /// and only for Health's Move into Slinky.
    func applyReview(_ review: FolderReview, name: String, changes: FolderChanges, picks: FolderChanges.Picks,
                     keyFiles: [ProjectScan.FoundFile], replaceExpected: Bool, trashAfter: Bool) {
        let summary = changes.summary(for: picks)
        let folders = review.folders.map(\.path)
        let files = keyFiles.map(Self.secretFile)
        let changedNames = Set(changes.changes.filter { picks.rows.contains($0.id) && [.new, .changed].contains(changes.status(of: $0, picks)) }.map(\.name))
        let target: (id: UUID, name: String)
        switch review.target {
        case .newProject: target = (UUID(), name)
        case let .project(id): target = (id, document.projects.first { $0.id == id }?.name ?? name)
        }
        let place = review.folders.first.map { ($0.path as NSString).abbreviatingWithTildeInPath }
            ?? review.file.map { ($0.path as NSString).abbreviatingWithTildeInPath }
        let entry = ActivityEntry(action: .imported, names: changes.changes.map(\.name).filter(changedNames.contains).uniqued() + files.map(\.name),
                                  detail: target.name + (place.map { ", from \($0)" } ?? ""))
        var text: String
        switch review.target {
        case .newProject: text = "Created \(target.name)" + (summary.changedAny ? ": \(summary.text)." : ".")
        case .project: text = summary.changedAny || summary.skipped > 0 ? "Updated \(target.name): \(summary.text)." : "\(target.name) is up to date."
        }
        if !files.isEmpty { text += " Saved \(counted(files.count, "file")) to Keys & Tokens." }
        let linking = !folders.isEmpty
        var saved = false
        animated {
            saved = change(text, undo: .records(name: review.target == .newProject ? "New Project" : "Update from Folder",
                                                undone: "Took back the import."),
                           activity: changedNames.isEmpty && files.isEmpty ? nil : entry, toastStyle: .success) { doc in
                switch review.target {
                case .newProject:
                    var project = Project(name: target.name, folders: folders)
                    project.id = target.id
                    changes.apply(picks, to: &project, replaceExpected: true)
                    doc.projects.append(project)
                case let .project(id):
                    guard let i = doc.projects.firstIndex(where: { $0.id == id }) else { return }
                    for folder in folders where !doc.projects[i].folders.contains(folder) { doc.projects[i].folders.append(folder) }
                    changes.apply(picks, to: &doc.projects[i], replaceExpected: replaceExpected && linking)
                }
                doc.secretFiles.insert(contentsOf: files, at: 0)
            }
        }
        guard saved else { return }
        Sounds.play(summary.new + summary.updated > 1 ? .imported : .saved)
        selection = .project(target.id)
        if trashAfter, let url = review.trashAfter, !isDemoMode { moveToTrash(url, writingExampleFrom: changes) }
    }

    /// Health › Move into Slinky, after the review saved: a names-only .env.example if there isn't one, then the
    /// .env to the Trash (where it can be put back).
    private func moveToTrash(_ url: URL, writingExampleFrom changes: FolderChanges) {
        let example = url.deletingLastPathComponent().appendingPathComponent(".env.example")
        if !FileManager.default.fileExists(atPath: example.path) {
            let names = changes.changes.filter { $0.status() != .onlyInSlinky }.map(\.name).uniqued()
            try? (names.map { "\($0)=" }.joined(separator: "\n") + "\n").write(to: example, atomically: true, encoding: .utf8)
        }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            animated { leaks.removeAll { if case let .envFile(path, _) = $0.place { return path == url.path }; return false } }
            show("Moved \(url.lastPathComponent) into Slinky. It's in the Trash, and .env.example has the names.")
        } catch {
            show("Saved the variables, but couldn't move \(url.lastPathComponent) to the Trash.", style: .info)
        }
    }

    /// A key file found in a folder, as it's kept in the vault.
    static func secretFile(_ found: ProjectScan.FoundFile) -> SecretFile {
        var fields: [String: String] = [:]
        if found.kind == .appStoreConnectKey, let id = SecretFile.keyID(fromFilename: found.fileName) { fields["Key ID"] = id }
        let name = found.kind == .appStoreConnectKey
            ? "App Store Connect API key" + (fields["Key ID"].map { " (\($0))" } ?? "")
            : (found.fileName as NSString).deletingPathExtension
        return SecretFile(name: name, filename: found.fileName, kind: found.kind, data: found.data, fields: fields,
                          note: "Found in \(found.id)")
    }
}

extension Array where Element: Hashable {
    /// Each element once, in order.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
