import Foundation

/// Installing the `slinky` command, the shell hook, and connecting AI tools. Each change to someone's config
/// files is shown first, backed up (`<file>.slinky-backup`) and can be undone with Disconnect.
@MainActor
enum Integrations {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    // MARK: The slinky command

    /// ~/.local/bin/slinky: a two-line script that runs this app's binary as the command.
    static var commandURL: URL { home.appendingPathComponent(".local/bin/slinky") }
    static var appBinary: String { Bundle.main.executablePath ?? "/Applications/Slinky.app/Contents/MacOS/Slinky" }

    static var commandScript: String {
        """
        #!/bin/sh
        # Installed by Slinky. Runs Slinky's own binary as the slinky command (Slinky checks it's really Slinky).
        exec "\(appBinary)" \(Command.marker) "$@"

        """
    }

    enum CommandState { case missing, installed, stale }

    static var commandState: CommandState {
        guard let text = try? String(contentsOf: commandURL, encoding: .utf8) else { return .missing }
        return text == commandScript ? .installed : .stale
    }

    static func installCommand() throws {
        try FileManager.default.createDirectory(at: commandURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try commandScript.write(to: commandURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: commandURL.path)
    }

    /// Whether ~/.local/bin is on the login shell's PATH.
    static func commandOnPath() async -> Bool {
        let path = await loginPath()
        return path.split(separator: ":").contains { $0 == commandURL.deletingLastPathComponent().path || $0 == "$HOME/.local/bin" }
    }

    /// The PATH a Terminal window gets (apps don't inherit it).
    static func loginPath() async -> String {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-lc", "print -r -- $PATH"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
            return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }

    // MARK: Git commit check

    /// Adds `slinky guard` to a repository's pre-commit hook (keeping whatever is there). Returns what happened.
    static func installGuard(in folder: String) throws -> String {
        if commandState != .installed { try installCommand() }
        let hooks = URL(fileURLWithPath: folder).appendingPathComponent(".git/hooks")
        guard FileManager.default.fileExists(atPath: hooks.deletingLastPathComponent().path) else { return "\((folder as NSString).lastPathComponent) isn't a git repository." }
        let hook = hooks.appendingPathComponent("pre-commit")
        let line = "\"\(commandURL.path)\" guard || exit 1"
        var text = (try? String(contentsOf: hook, encoding: .utf8)) ?? "#!/bin/sh\n"
        guard !text.contains("slinky\" guard") && !text.contains("slinky guard") else { return "The commit check is already in \((folder as NSString).lastPathComponent)." }
        text += (text.hasSuffix("\n") ? "" : "\n") + "# Added by Slinky: stop commits that contain secrets saved in Slinky.\n\(line)\n"
        try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        try text.write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        return "Commits in \((folder as NSString).lastPathComponent) are now checked for saved secrets."
    }

    // MARK: ~/.zshrc lines

    static var zshrc: URL { home.appendingPathComponent(".zshrc") }
    static let pathLine = #"export PATH="$HOME/.local/bin:$PATH""#
    static let hookLine = #"eval "$(slinky hook zsh)""#

    static func zshrcHas(_ line: String) -> Bool {
        ((try? String(contentsOf: zshrc, encoding: .utf8)) ?? "").contains(line)
    }

    static func addToZshrc(_ line: String, comment: String) throws {
        var text = (try? String(contentsOf: zshrc, encoding: .utf8)) ?? ""
        guard !text.contains(line) else { return }
        backup(zshrc)
        text += (text.isEmpty || text.hasSuffix("\n") ? "" : "\n") + "\n# \(comment) (added by Slinky)\n\(line)\n"
        try text.write(to: zshrc, atomically: true, encoding: .utf8)
    }

    static func removeFromZshrc(_ line: String) throws {
        guard let text = try? String(contentsOf: zshrc, encoding: .utf8), text.contains(line) else { return }
        backup(zshrc)
        var lines = text.components(separatedBy: "\n")
        if let i = lines.firstIndex(of: line) {
            lines.remove(at: i)
            if i > 0, lines[i - 1].hasSuffix("(added by Slinky)") { lines.remove(at: i - 1) }
        }
        try lines.joined(separator: "\n").write(to: zshrc, atomically: true, encoding: .utf8)
    }

    // MARK: AI tools

    enum Tool: String, CaseIterable, Identifiable {
        case claudeCode, cursor, codex, claudeDesktop
        var id: String { rawValue }

        var name: String {
            switch self {
            case .claudeCode: "Claude Code"
            case .cursor: "Cursor"
            case .codex: "Codex"
            case .claudeDesktop: "Claude"
            }
        }

        /// The file Connect edits.
        var file: URL {
            switch self {
            case .claudeCode: home.appendingPathComponent(".claude.json")
            case .cursor: home.appendingPathComponent(".cursor/mcp.json")
            case .codex: home.appendingPathComponent(".codex/config.toml")
            case .claudeDesktop: home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
            }
        }

        /// What Connect does, in plain words, before it does it.
        var preview: String {
            switch self {
            case .claudeCode:
                "Adds Slinky's MCP server to ~/.claude.json for all your projects, and tells Claude Code not to read .env files (~/.claude/settings.json)."
            case .cursor: "Adds Slinky's MCP server to ~/.cursor/mcp.json."
            case .codex: "Adds Slinky's MCP server to ~/.codex/config.toml."
            case .claudeDesktop: "Adds Slinky's MCP server to Claude's settings file."
            }
        }

        /// Whether the tool seems to be on this Mac at all.
        var isPresent: Bool {
            switch self {
            case .claudeCode: FileManager.default.fileExists(atPath: file.path) || FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude").path)
            case .cursor: FileManager.default.fileExists(atPath: home.appendingPathComponent(".cursor").path)
            case .codex: FileManager.default.fileExists(atPath: home.appendingPathComponent(".codex").path)
            case .claudeDesktop: FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path)
            }
        }
    }

    static var serverEntry: [String: Any] { ["command": commandURL.path, "args": ["mcp"]] }

    static func isConnected(_ tool: Tool) -> Bool {
        switch tool {
        case .codex:
            return ((try? String(contentsOf: tool.file, encoding: .utf8)) ?? "").contains("[mcp_servers.slinky]")
        default:
            let json = readJSON(tool.file)
            return (json["mcpServers"] as? [String: Any])?["slinky"] != nil
        }
    }

    static func connect(_ tool: Tool) throws {
        if commandState != .installed { try installCommand() }
        switch tool {
        case .codex:
            var text = (try? String(contentsOf: tool.file, encoding: .utf8)) ?? ""
            guard !text.contains("[mcp_servers.slinky]") else { return }
            backup(tool.file)
            text += (text.isEmpty || text.hasSuffix("\n") ? "" : "\n") + """

            # Slinky (added by Slinky): names only; run commands with `slinky run -- …`.
            [mcp_servers.slinky]
            command = "\(commandURL.path)"
            args = ["mcp"]

            """
            try FileManager.default.createDirectory(at: tool.file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: tool.file, atomically: true, encoding: .utf8)
        case .claudeCode:
            // Claude Code rewrites ~/.claude.json all the time, so ask its own command to add the server.
            if runLogin(#"claude mcp add --scope user slinky -- "$0" mcp"#, commandURL.path) != 0 {
                var json = readJSON(tool.file)
                var servers = json["mcpServers"] as? [String: Any] ?? [:]
                servers["slinky"] = serverEntry.merging(["type": "stdio"]) { a, _ in a }
                json["mcpServers"] = servers
                try writeJSON(json, to: tool.file)
            }
            try denyEnvReads()
        default:
            var json = readJSON(tool.file)
            var servers = json["mcpServers"] as? [String: Any] ?? [:]
            servers["slinky"] = serverEntry
            json["mcpServers"] = servers
            try writeJSON(json, to: tool.file)
        }
    }

    static func disconnect(_ tool: Tool) throws {
        switch tool {
        case .codex:
            guard var text = try? String(contentsOf: tool.file, encoding: .utf8) else { return }
            backup(tool.file)
            if let start = text.range(of: "\n# Slinky (added by Slinky)") ?? text.range(of: "[mcp_servers.slinky]") {
                let after = text[start.upperBound...]
                let end = after.range(of: "\n[")?.lowerBound ?? text.endIndex
                text.removeSubrange(start.lowerBound..<end)
            }
            try text.write(to: tool.file, atomically: true, encoding: .utf8)
        case .claudeCode:
            if runLogin("claude mcp remove --scope user slinky") != 0 {
                var json = readJSON(tool.file)
                guard var servers = json["mcpServers"] as? [String: Any], servers["slinky"] != nil else { return }
                servers["slinky"] = nil
                json["mcpServers"] = servers
                try writeJSON(json, to: tool.file)
            }
        default:
            var json = readJSON(tool.file)
            guard var servers = json["mcpServers"] as? [String: Any], servers["slinky"] != nil else { return }
            servers["slinky"] = nil
            json["mcpServers"] = servers
            try writeJSON(json, to: tool.file)
        }
    }

    /// Claude Code: deny reading .env files, so values never land in a transcript.
    private static func denyEnvReads() throws {
        let url = home.appendingPathComponent(".claude/settings.json")
        var json = readJSON(url)
        var permissions = json["permissions"] as? [String: Any] ?? [:]
        var deny = permissions["deny"] as? [String] ?? []
        for rule in ["Read(./.env)", "Read(./.env.*)", "Read(**/.env)", "Read(**/.env.*)"] where !deny.contains(rule) { deny.append(rule) }
        permissions["deny"] = deny
        json["permissions"] = permissions
        try writeJSON(json, to: url)
    }

    /// Runs a line in a login shell (so the person's PATH applies). Extra arguments arrive as $0, $1…, unquoted-safe.
    @discardableResult
    static func runLogin(_ script: String, _ args: String...) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", script] + args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    // MARK: Files

    private static func readJSON(_ url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }

    private static func writeJSON(_ json: [String: Any], to url: URL) throws {
        backup(url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    /// One backup next to the file, made before Slinky's first change to it.
    private static func backup(_ url: URL) {
        let copy = url.appendingPathExtension("slinky-backup")
        guard FileManager.default.fileExists(atPath: url.path), !FileManager.default.fileExists(atPath: copy.path) else { return }
        try? FileManager.default.copyItem(at: url, to: copy)
    }
}
