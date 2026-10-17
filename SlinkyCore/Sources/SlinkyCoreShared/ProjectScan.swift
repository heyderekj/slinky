import Foundation

/// What Slinky finds in a project folder before creating a project from it:
/// its .env files (variable names only), the names in .env.example, and whether .gitignore covers each file.
/// Read-only. Slinky never writes to, moves or deletes anything in the folder.
public struct ProjectScan: Sendable, Equatable {
    public struct EnvFile: Sendable, Equatable, Identifiable {
        public var id: String { fileName }
        public let fileName: String
        public let url: URL
        /// Slinky's guess from the file name. The person can change it.
        public let environment: AppEnvironment
        public let lines: [DotEnvLine]
        /// nil when the folder isn't a git repository (nothing to warn about).
        public let ignoredByGit: Bool?

        public var names: [String] { lines.map(\.name) }
    }

    public let folder: URL
    public let suggestedName: String
    public let envFiles: [EnvFile]
    /// The .env.example (or .sample, .template, .dist) that lists what the project expects.
    public let exampleFile: String?
    public let expected: [String]
    public let isGitRepo: Bool

    public static func scan(_ folder: URL, fileManager: FileManager = .default) -> ProjectScan {
        let names = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        let isGitRepo = names.contains(".git")
        let patterns = (try? String(contentsOf: folder.appendingPathComponent(".gitignore"), encoding: .utf8))
            .map(gitignorePatterns) ?? []

        var envFiles: [EnvFile] = []
        var exampleFile: String?
        var expected: [String] = []
        for name in names.sorted() where isEnvFile(name) {
            let url = folder.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue,
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if isExample(name) {
                if exampleFile == nil {
                    exampleFile = name
                    expected = DotEnv.names(text)
                }
                continue
            }
            envFiles.append(EnvFile(fileName: name, url: url, environment: environment(for: name),
                                    lines: DotEnv.parse(text),
                                    ignoredByGit: isGitRepo ? isIgnored(name, by: patterns) : nil))
        }
        let order: [AppEnvironment] = [.local, .preview, .production]
        envFiles.sort { (order.firstIndex(of: $0.environment)!, $0.fileName) < (order.firstIndex(of: $1.environment)!, $1.fileName) }
        return ProjectScan(folder: folder, suggestedName: folder.lastPathComponent, envFiles: envFiles,
                           exampleFile: exampleFile, expected: expected, isGitRepo: isGitRepo)
    }

    /// `.env`, `.env.local`, `.env.production`, `.dev.vars` (Cloudflare) and the example files.
    public static func isEnvFile(_ name: String) -> Bool {
        name == ".env" || name.hasPrefix(".env.") || name == ".dev.vars"
    }

    public static func isExample(_ name: String) -> Bool {
        [".example", ".sample", ".template", ".dist"].contains { name.lowercased().hasSuffix($0) }
    }

    public static func environment(for name: String) -> AppEnvironment {
        let n = name.lowercased()
        if n.contains("prod") { return .production }
        if n.contains("preview") || n.contains("staging") || n.contains("stage") { return .preview }
        return .local
    }

    // MARK: .gitignore (the common cases, not every rule git has)

    static func gitignorePatterns(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasSuffix("/") }
    }

    /// Last matching pattern wins, and `!pattern` un-ignores, the way git reads it.
    public static func isIgnored(_ name: String, by patterns: [String]) -> Bool {
        var ignored = false
        for raw in patterns {
            let negated = raw.hasPrefix("!")
            var pattern = negated ? String(raw.dropFirst()) : raw
            if pattern.hasPrefix("**/") { pattern.removeFirst(3) }
            if pattern.hasPrefix("/") { pattern.removeFirst() }
            if fnmatch(pattern, name, FNM_PERIOD) == 0 || (pattern.hasPrefix(".") && fnmatch(pattern, name, 0) == 0) {
                ignored = !negated
            }
        }
        return ignored
    }
}
