import Foundation

/// What Slinky finds in a project folder before creating or updating a project from it: its .env files (with
/// their lines), the names in example files, whether .gitignore covers each file, and key files worth keeping.
/// Looks into subfolders (`apps/web/.env.local`) up to `depth` levels, skipping dependencies and build output.
/// Read-only. Slinky never writes to, moves or deletes anything in the folder.
public struct ProjectScan: Sendable, Equatable {
    public struct EnvFile: Sendable, Equatable, Identifiable {
        /// The path inside the scanned folder: ".env.local", "apps/web/.env.local".
        public var id: String { folder.isEmpty ? fileName : folder + "/" + fileName }
        public let fileName: String
        /// The subfolder it's in, "" for the scanned folder itself.
        public let folder: String
        public let url: URL
        /// Slinky's guess from the file name. The person can change it.
        public let environment: AppEnvironment
        public let lines: [DotEnvLine]
        /// nil when the folder isn't in a git repository (nothing to warn about).
        public let ignoredByGit: Bool?

        public var names: [String] { lines.map(\.name) }

        public init(fileName: String, folder: String = "", url: URL, environment: AppEnvironment,
                    lines: [DotEnvLine], ignoredByGit: Bool?) {
            self.fileName = fileName
            self.folder = folder
            self.url = url
            self.environment = environment
            self.lines = lines
            self.ignoredByGit = ignoredByGit
        }
    }

    /// A .env.example (or .sample, .template, .dist): names only.
    public struct Example: Sendable, Equatable, Identifiable {
        public let id: String
        public let names: [String]
        public init(id: String, names: [String]) { self.id = id; self.names = names }
    }

    /// A key file found in the folder: an App Store Connect .p8, a private key, a service account.
    public struct FoundFile: Sendable, Equatable, Identifiable {
        public let id: String
        public let url: URL
        public let data: Data
        public let kind: SecretFile.Kind
        /// Under test/, fixtures/, examples/…: probably not a real key.
        public let likelyFixture: Bool
        public var fileName: String { url.lastPathComponent }
        public init(id: String, url: URL, data: Data, kind: SecretFile.Kind, likelyFixture: Bool) {
            self.id = id; self.url = url; self.data = data; self.kind = kind; self.likelyFixture = likelyFixture
        }
    }

    public let folder: URL
    public let suggestedName: String
    public let envFiles: [EnvFile]
    public let examples: [Example]
    /// Env-like files left alone on purpose (`.env.vault`, `.env.keys`), by path.
    public let skippedFiles: [String]
    public let secretFiles: [FoundFile]
    /// Subfolders with something in them, the scanned folder ("") first.
    public let groups: [String]
    public let isGitRepo: Bool

    /// The first example file, for places that show one.
    public var exampleFile: String? { examples.first?.id }
    /// Every name the example files list, each once, in order.
    public var expected: [String] {
        var seen = Set<String>()
        return examples.flatMap(\.names).filter { seen.insert($0).inserted }
    }

    public init(folder: URL, suggestedName: String? = nil, envFiles: [EnvFile], examples: [Example] = [],
                skippedFiles: [String] = [], secretFiles: [FoundFile] = [], isGitRepo: Bool = false) {
        self.folder = folder
        self.suggestedName = suggestedName ?? folder.lastPathComponent
        self.envFiles = envFiles
        self.examples = examples
        self.skippedFiles = skippedFiles
        self.secretFiles = secretFiles
        self.isGitRepo = isGitRepo
        var groups = [String]()
        for g in envFiles.map(\.folder) + examples.map { Self.folderOf($0.id) } + secretFiles.map { Self.folderOf($0.id) }
        where !groups.contains(g) { groups.append(g) }
        self.groups = groups.sorted { ($0.isEmpty ? 0 : 1, $0) < ($1.isEmpty ? 0 : 1, $1) }
    }

    /// Dependencies, build output and caches: never a project's own settings.
    public static let skippedFolders: Set<String> = [
        ".git", "node_modules", ".build", "build", "dist", ".next", ".nuxt", ".svelte-kit", "Pods", "DerivedData",
        "vendor", ".venv", "venv", "__pycache__", ".turbo", ".cache", "target", "coverage", ".vercel", ".output",
        "out", ".expo", ".gradle", ".idea", ".swiftpm",
    ]

    /// Reads `folder`, and its subfolders `depth` levels down. `secretFiles` also looks for key files.
    public static func scan(_ folder: URL, depth: Int = 0, secretFiles findFiles: Bool = false,
                            fileManager: FileManager = .default) -> ProjectScan {
        let repo = gitRoot(of: folder, fileManager: fileManager)
        var envFiles: [EnvFile] = []
        var examples: [Example] = []
        var skipped: [String] = []
        var found: [FoundFile] = []
        var ignoreCache: [String: [String]] = [:]

        func visit(_ url: URL, relative: String, level: Int) {
            guard let names = try? fileManager.contentsOfDirectory(atPath: url.path) else { return }
            for name in names.sorted() {
                let child = url.appendingPathComponent(name)
                let path = relative.isEmpty ? name : relative + "/" + name
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: child.path, isDirectory: &isDir) else { continue }
                if isDir.boolValue {
                    // A Python virtualenv is often called .env: a folder, never settings.
                    if level < depth, !skippedFolders.contains(name), !isEnvFile(name), !name.hasSuffix(".app") {
                        visit(child, relative: path, level: level + 1)
                    }
                    continue
                }
                if isSkipped(name) { skipped.append(path); continue }
                if isEnvFile(name) {
                    guard let text = try? String(contentsOf: child, encoding: .utf8) else { continue }
                    if isExample(name) {
                        examples.append(Example(id: path, names: DotEnv.names(text)))
                    } else {
                        let ignored = repo.map { isIgnored(path: path, in: folder, repo: $0, cache: &ignoreCache, fileManager: fileManager) }
                        envFiles.append(EnvFile(fileName: name, folder: relative, url: child, environment: environment(for: name),
                                                lines: DotEnv.parse(text), ignoredByGit: ignored))
                    }
                } else if findFiles, SecretFile.mightBeSecret(filename: name),
                          let size = (try? fileManager.attributesOfItem(atPath: child.path))?[.size] as? Int,
                          size <= SecretFile.maxBytes, let data = try? Data(contentsOf: child),
                          SecretFile.looksSecret(filename: name, data: data) {
                    found.append(FoundFile(id: path, url: child, data: data, kind: SecretFile.guessKind(filename: name, data: data),
                                           likelyFixture: isLikelyFixture(path)))
                }
            }
        }
        visit(folder, relative: "", level: 0)

        let order: [AppEnvironment] = [.local, .preview, .production]
        envFiles.sort {
            ($0.folder.isEmpty ? 0 : 1, $0.folder, order.firstIndex(of: $0.environment)!, precedence(of: $0.fileName), $0.fileName)
                < ($1.folder.isEmpty ? 0 : 1, $1.folder, order.firstIndex(of: $1.environment)!, precedence(of: $1.fileName), $1.fileName)
        }
        return ProjectScan(folder: folder, envFiles: envFiles, examples: examples, skippedFiles: skipped,
                           secretFiles: found, isGitRepo: repo != nil)
    }

    /// One dropped file, read the same way (its folder's .gitignore applies).
    public static func scan(file: URL, fileManager: FileManager = .default) -> ProjectScan {
        let folder = file.deletingLastPathComponent()
        let name = file.lastPathComponent
        let repo = gitRoot(of: folder, fileManager: fileManager)
        guard isEnvFile(name), !isSkipped(name), let text = try? String(contentsOf: file, encoding: .utf8) else {
            return ProjectScan(folder: folder, envFiles: [], skippedFiles: isSkipped(name) ? [name] : [], isGitRepo: repo != nil)
        }
        if isExample(name) {
            return ProjectScan(folder: folder, envFiles: [], examples: [Example(id: name, names: DotEnv.names(text))], isGitRepo: repo != nil)
        }
        var cache: [String: [String]] = [:]
        let ignored = repo.map { isIgnored(path: name, in: folder, repo: $0, cache: &cache, fileManager: fileManager) }
        return ProjectScan(folder: folder, envFiles: [EnvFile(fileName: name, url: file, environment: environment(for: name),
                                                              lines: DotEnv.parse(text), ignoredByGit: ignored)],
                           isGitRepo: repo != nil)
    }

    /// Every name the example files in these folders list, each once, in order. For a project's "missing".
    public static func expectedNames(inFolders folders: [URL], depth: Int = 3, fileManager: FileManager = .default) -> [String] {
        var seen = Set<String>()
        return folders.flatMap { scan($0, depth: depth, fileManager: fileManager).expected }.filter { seen.insert($0).inserted }
    }

    /// `.env`, `.env.local`, `.env.production`, `.dev.vars` (Cloudflare) and the example files.
    public static func isEnvFile(_ name: String) -> Bool {
        name == ".env" || name.hasPrefix(".env.") || name == ".dev.vars"
    }

    /// Env-like files that hold something else: dotenv-vault's encrypted copy and keys, dotenvx's keys.
    public static func isSkipped(_ name: String) -> Bool {
        let n = name.lowercased()
        return n == ".env.vault" || n == ".env.keys" || n == ".env.me" || n.hasPrefix(".env.vault.")
    }

    public static func isExample(_ name: String) -> Bool {
        [".example", ".sample", ".template", ".dist"].contains { name.lowercased().hasSuffix($0) }
    }

    /// The environment a file name says, or nil when it doesn't say (`.env`, `.dev.vars`).
    public static func environmentHint(for name: String) -> AppEnvironment? {
        let n = (name as NSString).lastPathComponent.lowercased()
        if n == ".env" || n == ".dev.vars" { return nil }
        if n.contains("prod") { return .production }
        if n.contains("preview") || n.contains("staging") || n.contains("stage") { return .preview }
        return .local
    }

    public static func environment(for name: String) -> AppEnvironment {
        environmentHint(for: name) ?? .local
    }

    /// Which file wins when two set the same name for one environment, the way Next.js and Vite load them:
    /// `.env` < `.env.production` < `.env.local` < `.env.production.local`.
    public static func precedence(of name: String) -> Int {
        let n = (name as NSString).lastPathComponent.lowercased()
        if n == ".env" { return 0 }
        if n == ".env.local" { return 2 }
        if n.hasPrefix(".env.") && n.hasSuffix(".local") { return 3 }
        return 1
    }

    /// Paths under test/, fixtures/, examples/ and the like: probably sample keys, not real ones.
    public static func isLikelyFixture(_ path: String) -> Bool {
        let fixtures: Set<String> = ["test", "tests", "__tests__", "spec", "specs", "fixture", "fixtures", "example", "examples",
                                     "sample", "samples", "mock", "mocks", "e2e", "testdata", "__fixtures__"]
        return path.lowercased().split(separator: "/").dropLast().contains { fixtures.contains(String($0)) }
    }

    static func folderOf(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    // MARK: .gitignore (the common cases, not every rule git has)

    static func gitignorePatterns(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// The repository the folder is in: the folder itself or one of its five nearest parents.
    static func gitRoot(of folder: URL, fileManager: FileManager) -> URL? {
        var dir = folder.standardizedFileURL
        for _ in 0...5 {
            if fileManager.fileExists(atPath: dir.appendingPathComponent(".git").path) { return dir }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { return nil }
            dir = parent
        }
        return nil
    }

    /// Whether git ignores `path` (relative to `folder`), reading every .gitignore from the repository's root down
    /// to the file's own folder, each against the path below it.
    static func isIgnored(path: String, in folder: URL, repo: URL, cache: inout [String: [String]],
                          fileManager: FileManager) -> Bool {
        let file = folder.appendingPathComponent(path).standardizedFileURL.path
        let root = repo.standardizedFileURL.path
        guard file.hasPrefix(root + "/") else { return false }
        let fromRoot = String(file.dropFirst(root.count + 1))
        let parts = fromRoot.split(separator: "/").map(String.init)
        var ignored = false
        for level in 0..<parts.count {
            let dirPath = parts.prefix(level).joined(separator: "/")
            let patterns = cache[dirPath] ?? {
                let url = dirPath.isEmpty ? repo : repo.appendingPathComponent(dirPath)
                let p = (try? String(contentsOf: url.appendingPathComponent(".gitignore"), encoding: .utf8)).map(gitignorePatterns) ?? []
                cache[dirPath] = p
                return p
            }()
            if let verdict = matches(Array(parts.dropFirst(level)), patterns: patterns) { ignored = verdict }
        }
        return ignored
    }

    /// The last pattern that matches a path (relative to its .gitignore) decides: true ignored, false un-ignored.
    static func matches(_ parts: [String], patterns: [String]) -> Bool? {
        var verdict: Bool?
        let path = parts.joined(separator: "/")
        for raw in patterns {
            let negated = raw.hasPrefix("!")
            var pattern = negated ? String(raw.dropFirst()) : raw
            let dirOnly = pattern.hasSuffix("/")
            if dirOnly { pattern.removeLast() }
            if pattern.hasPrefix("**/") { pattern.removeFirst(3) }
            let anchored = pattern.hasPrefix("/") || pattern.contains("/")
            if pattern.hasPrefix("/") { pattern.removeFirst() }
            var hit = false
            if dirOnly {
                // A folder pattern ignores everything under a folder it matches.
                for i in 0..<max(parts.count - 1, 0) {
                    let candidate = anchored ? parts.prefix(i + 1).joined(separator: "/") : parts[i]
                    if fnmatch(pattern, candidate, anchored ? FNM_PATHNAME : 0) == 0 { hit = true; break }
                }
            } else if anchored {
                hit = fnmatch(pattern, path, FNM_PATHNAME) == 0
            } else {
                hit = isIgnored(parts.last ?? "", by: [pattern])
            }
            if hit { verdict = !negated }
        }
        return verdict
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
