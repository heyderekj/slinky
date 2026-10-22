import Foundation

/// What the `slinky` command and the app say to each other over the local socket. One JSON line each way.
/// Values only ever travel app → CLI, for a command the person approved, and only to the CLI (the same
/// signed binary as the app; the app checks). Nothing here is logged.
public enum Broker {
    /// ~/Library/Application Support/Slinky/slinky.sock, next to the vault, in a folder only you can open.
    public static var socketURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Slinky/slinky.sock")
    }

    public struct Request: Codable, Sendable {
        public enum Op: String, Codable, Sendable {
            case status, list, projectForDir, env, check, request, guardDiff, notarize
            /// Added in 1.5: lock the vault, show Slinky (and an item by name), a project's variable names.
            case lock, open, names
        }
        public enum Purpose: String, Codable, Sendable { case run, export, xcconfig }

        public var op: Op
        public var cwd: String
        public var argv: [String]
        public var purpose: Purpose?
        public var project: String?
        public var environment: String?
        public var keys: [String]
        /// Secret files by name, optionally NAME=ENV_VAR for the variable that gets the temp file's path.
        public var files: [String]?
        /// Environment markers from the asking process (CLAUDECODE, CURSOR_AGENT…), as hints.
        public var markers: [String: String]
        public var name: String?
        public var reason: String?
        public var text: String?

        public init(op: Op, cwd: String = FileManager.default.currentDirectoryPath, argv: [String] = [], purpose: Purpose? = nil,
                    project: String? = nil, environment: String? = nil, keys: [String] = [], markers: [String: String] = [:],
                    name: String? = nil, reason: String? = nil, text: String? = nil) {
            self.op = op; self.cwd = cwd; self.argv = argv; self.purpose = purpose; self.project = project
            self.environment = environment; self.keys = keys; self.markers = markers; self.name = name
            self.reason = reason; self.text = text
        }
    }

    public struct Response: Codable, Sendable {
        public var ok: Bool
        public var message: String?
        public var unlocked: Bool?
        public var project: String?
        /// Values, only for an approved env request.
        public var env: [String: String]?
        /// Names only: listed items, missing variables, held-back variables, or what a diff contains.
        public var names: [String]?
        public var withheld: [String]?
        public var lines: [String]?
        /// For an approved run: env variable → [file name, base64 contents]. Written to a 0600 temp file for the run only.
        public var files: [String: [String]]?

        public init(ok: Bool, message: String? = nil) { self.ok = ok; self.message = message }
        public static func fail(_ message: String) -> Response { Response(ok: false, message: message) }
    }

    /// "App Store Connect API key" → APP_STORE_CONNECT_API_KEY_PATH, unless the person named the variable (NAME=VAR).
    public static func fileVariable(_ spec: String) -> (name: String, variable: String) {
        if let eq = spec.firstIndex(of: "=") {
            return (String(spec[..<eq]), String(spec[spec.index(after: eq)...]))
        }
        let base = spec.uppercased().map { $0.isLetter || $0.isNumber ? $0 : "_" }
        let collapsed = String(base).split(separator: "_").joined(separator: "_")
        return (spec, collapsed + "_PATH")
    }

    /// The markers agents set in the shells they run. Hints only: the app also looks at the process tree.
    public static let agentMarkers = ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CURSOR_AGENT", "CODEX_SANDBOX", "CODEX_SANDBOX_NETWORK_DISABLED", "GEMINI_CLI"]

    /// Process names that mean an AI agent is asking.
    public static let agentProcesses: [String: String] = [
        "claude": "Claude Code", "codex": "Codex", "cursor-agent": "Cursor", "gemini": "Gemini CLI", "aider": "Aider", "opencode": "OpenCode",
    ]

    /// Environment variables that could change what a command runs. Removed before secrets are handed over.
    public static func isStripped(_ name: String) -> Bool {
        ["NODE_OPTIONS", "BASH_ENV", "ENV", "LD_PRELOAD", "PYTHONSTARTUP", "PERL5OPT", "RUBYOPT"].contains(name) || name.hasPrefix("DYLD_")
    }

    /// Commands an agent may not run with secrets: shells and evaluators, tools that print the environment,
    /// and tools that send things off the Mac. A person running `slinky run` themselves isn't limited.
    public static func agentRefusal(_ argv: [String]) -> String? {
        guard let first = argv.first else { return "No command given." }
        let tool = (first as NSString).lastPathComponent
        let rest = Set(argv.dropFirst())
        if ["sh", "bash", "zsh", "fish", "env", "printenv", "export", "set", "curl", "wget", "nc", "ncat", "ssh", "scp",
            "osascript", "open", "pbcopy", "tee", "cat", "echo", "printf"].contains(tool) {
            return "\(tool) can't be run with secrets by an agent. Use the project's own script instead (npm run dev, make test…)."
        }
        if ["node", "python", "python3", "ruby", "perl", "deno", "bun"].contains(tool), !rest.isDisjoint(with: ["-e", "-c", "--eval", "-p", "--print"]) {
            return "Inline code can't be run with secrets by an agent. Put it in a script file first."
        }
        if tool == "git", rest.contains("push") { return "git push can't be run with secrets by an agent." }
        if ["npm", "pnpm", "yarn", "bun"].contains(tool), rest.contains("publish") { return "Publishing can't be run with secrets by an agent." }
        return nil
    }

    /// `export NAME='value'` lines for a shell, safe for any value (single quotes, with ' written as '\'').
    public static func shellExports(_ env: [String: String]) -> String {
        let lines = env.keys.sorted().map { name in "export \(name)='\(env[name]!.replacingOccurrences(of: "'", with: "'\\''"))'" }
        return (lines + ["export _SLINKY_NAMES='\(env.keys.sorted().joined(separator: " "))'"]).joined(separator: "\n")
    }

    /// A .xcconfig for Xcode. "//" starts a comment there, so it's written as "/$()/" (an empty variable between).
    public static func xcconfig(_ env: [String: String], project: String) -> String {
        let header = "// Made by Slinky for \(project). Don't commit this file.\n"
        return header + env.keys.sorted().map { "\($0) = \(env[$0]!.replacingOccurrences(of: "//", with: "/$()/"))" }.joined(separator: "\n") + "\n"
    }

    /// Whether `path` is inside one of `folders` (after resolving symlinks).
    public static func path(_ path: String, isInside folders: [String]) -> Bool {
        let p = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return folders.contains { f in
            let base = URL(fileURLWithPath: f).resolvingSymlinksInPath().path
            return p == base || p.hasPrefix(base.hasSuffix("/") ? base : base + "/")
        }
    }
}
