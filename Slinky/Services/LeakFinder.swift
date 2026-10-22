import Foundation
import SlinkyCoreShared

/// A saved value found somewhere outside Slinky. Names and places only; kept in memory, never written down.
struct LeakFinding: Identifiable, Hashable, Sendable {
    enum Place: Hashable, Sendable {
        /// A .env file (not .env.example) in a linked project: one click moves it into Slinky.
        case envFile(path: String, projectID: UUID?)
        /// Any other file in a linked project.
        case projectFile(path: String, project: String)
        /// A commit in a linked project's git history.
        case commit(repo: String, hash: String, project: String)
        /// An AI tool's saved conversation.
        case transcript(tool: String, path: String)
        /// Shell history: one click removes those lines.
        case history(path: String)
    }

    let place: Place
    let names: [String]
    var id: Place { place }

    var title: String {
        let what = names.count == 1 ? names[0] : "\(names[0]) and \(names.count - 1) more"
        let verb = names.count == 1 ? "is" : "are"
        switch place {
        case let .envFile(path, _): return "\(what) \(verb) in \((path as NSString).lastPathComponent)"
        case let .projectFile(path, _): return "\(what) \(verb) written in \((path as NSString).lastPathComponent)"
        case let .commit(_, hash, project): return "\(what) \(verb) in a \(project) commit (\(hash))"
        case let .transcript(tool, _): return "\(what) \(verb) in a \(tool) conversation"
        case let .history(path): return "\(what) \(verb) in your shell history (\((path as NSString).lastPathComponent))"
        }
    }

    var detail: String {
        switch place {
        case .envFile: return "A plain-text file in your project. Move it into Slinky and leave a .env.example with names only."
        case let .projectFile(_, project): return "In \(project). Take it out, and if it was ever shared, make a new key."
        case .commit: return "Git keeps it even after it's deleted. If this repository was ever pushed, make a new key."
        case .transcript: return "Saved conversations can be read by anything on this Mac. Consider making a new key."
        case .history: return "Commands you typed with the value in them. Removing those lines keeps the rest of your history."
        }
    }

    /// Where it is, for its own line under the detail ("~/…/file"). Shell history needs none.
    var shownPath: String? {
        if case .history = place { return nil }
        return short(path)
    }

    var path: String {
        switch place {
        case let .envFile(p, _), let .projectFile(p, _), let .transcript(_, p), let .history(p): p
        case let .commit(repo, _, _): repo
        }
    }

    private func short(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }
}

/// Looks for exact copies of saved values. Reads files on this Mac only; nothing is sent anywhere.
nonisolated enum LeakFinder {
    struct ProjectRef: Sendable { let id: UUID; let name: String; let folders: [String] }

    private static let skipDirs: Set<String> = [".git", "node_modules", ".build", "build", "dist", ".next", ".nuxt", ".svelte-kit",
                                                "Pods", "DerivedData", "vendor", ".venv", "venv", "__pycache__", ".turbo", ".cache", "target", "coverage"]
    private static let skipExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "mp4", "mov", "zip", "dmg", "pdf",
                                                      "woff", "woff2", "ttf", "otf", "ico", "a", "o", "dylib", "car"]
    private static let maxFileBytes = 4 * 1024 * 1024

    static func scan(secrets: [LeakScanner.Secret], projects: [ProjectRef]) async -> [LeakFinding] {
        await Task.detached(priority: .utility) {
            var out: [LeakFinding] = []
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser

            // Linked project folders.
            for project in projects {
                for folder in project.folders {
                    let root = URL(fileURLWithPath: folder)
                    guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                                                     options: [.skipsPackageDescendants]) else { continue }
                    var count = 0
                    while let url = walker.nextObject() as? URL, count < 20_000 {
                        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                        if values?.isDirectory == true {
                            if skipDirs.contains(url.lastPathComponent) { walker.skipDescendants() }
                            continue
                        }
                        count += 1
                        guard (values?.fileSize ?? 0) <= maxFileBytes, !skipExtensions.contains(url.pathExtension.lowercased()),
                              let data = try? Data(contentsOf: url) else { continue }
                        let names = LeakScanner.matches(in: data, secrets: secrets)
                        guard !names.isEmpty else { continue }
                        let name = url.lastPathComponent
                        if ProjectScan.isEnvFile(name), !ProjectScan.isExample(name) {
                            out.append(LeakFinding(place: .envFile(path: url.path, projectID: project.id), names: names))
                        } else {
                            out.append(LeakFinding(place: .projectFile(path: url.path, project: project.name), names: names))
                        }
                    }
                    // Git history (most recent 400 commits, every branch).
                    if fm.fileExists(atPath: root.appendingPathComponent(".git").path) {
                        out += commits(in: root, project: project.name, secrets: secrets)
                    }
                }
            }

            // AI tools' saved conversations.
            let transcripts: [(String, URL)] = [
                ("Claude Code", home.appendingPathComponent(".claude/projects")),
                ("Codex", home.appendingPathComponent(".codex/sessions")),
                ("Cursor", home.appendingPathComponent("Library/Application Support/Cursor/User/workspaceStorage")),
                ("Cursor", home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage")),
            ]
            for (tool, dir) in transcripts {
                guard let walker = fm.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
                while let url = walker.nextObject() as? URL {
                    guard ["jsonl", "json", "vscdb"].contains(url.pathExtension),
                          let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 200 * 1024 * 1024,
                          let data = try? Data(contentsOf: url, options: .alwaysMapped) else { continue }
                    let names = LeakScanner.matches(in: data, secrets: secrets)
                    if !names.isEmpty { out.append(LeakFinding(place: .transcript(tool: tool, path: url.path), names: names)) }
                }
            }

            // Shell history.
            for file in [".zsh_history", ".bash_history", ".local/share/fish/fish_history"] {
                let url = home.appendingPathComponent(file)
                guard let data = try? Data(contentsOf: url) else { continue }
                let names = LeakScanner.matches(in: data, secrets: secrets)
                if !names.isEmpty { out.append(LeakFinding(place: .history(path: url.path), names: names)) }
            }
            return out
        }.value
    }

    /// Commits whose changes contain a saved value, newest first, one finding per commit.
    private static func commits(in repo: URL, project: String, secrets: [LeakScanner.Secret]) -> [LeakFinding] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", repo.path, "log", "-p", "--all", "--no-color", "--format=commit %h", "-n", "400"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        var data = Data()
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty || data.count > 200 * 1024 * 1024 { break }
            data.append(chunk)
        }
        p.terminate()
        var out: [LeakFinding] = []
        let text = String(decoding: data, as: UTF8.self)
        for chunk in text.components(separatedBy: "\ncommit ") {
            let names = LeakScanner.matches(in: chunk, secrets: secrets)
            guard !names.isEmpty else { continue }
            let head = chunk.hasPrefix("commit ") ? chunk.dropFirst("commit ".count) : Substring(chunk)
            let hash = String(head.prefix(while: { !$0.isWhitespace }))
            out.append(LeakFinding(place: .commit(repo: repo.path, hash: hash, project: project), names: names))
        }
        return out
    }

    /// Shell history without the lines that contain those values. Works on bytes, so odd encodings survive.
    static func cleanHistory(at path: String, values: [String]) throws -> Int {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let needles = values.filter { $0.count >= LeakScanner.minLength }.map { Data($0.utf8) }
        var kept = Data()
        var removed = 0
        for line in data.split(separator: 10, omittingEmptySubsequences: false) {
            let lineData = Data(line)
            if needles.contains(where: { lineData.range(of: $0) != nil }) { removed += 1; continue }
            if !kept.isEmpty { kept.append(10) }
            kept.append(lineData)
        }
        if removed > 0 { try kept.write(to: url, options: .atomic) }
        return removed
    }
}
