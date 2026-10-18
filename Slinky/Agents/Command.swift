import Darwin
import Foundation
import SlinkyCoreShared

/// The `slinky` command. It's Slinky's own binary started with `--slinky-cli` (the installed `slinky` script
/// does that), so the app can check by code signature that it's really Slinky asking. It never opens the vault:
/// it asks the app, which asks you.
nonisolated enum Command {
    static let marker = "--slinky-cli"

    static func run(_ args: [String]) -> Int32 {
        var args = args
        let command = args.isEmpty ? "help" : args.removeFirst()
        switch command {
        case "run": return runCommand(args)
        case "env": return envCommand(args)
        case "xcconfig": return xcconfigCommand(args)
        case "ls", "list": return listCommand()
        case "check": return checkCommand(args)
        case "status": return statusCommand()
        case "guard": return guardCommand(args)
        case "hook": return hookCommand(args)
        case "project-for-dir": return projectForDirCommand()
        case "notarize-profile": return notarizeCommand(args)
        case "request": return requestCommand(args)
        case "mcp": return MCPServer.run(send: { send($0) })
        case "detect":
            let text = args.isEmpty ? String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self) : args.joined(separator: " ")
            print(Detector.detect(text).map { "\($0.label) → \($0.destination.title)" } ?? "Nothing to look at.")
            return 0
        case "version", "--version": print("slinky \(version)"); return 0
        default: print(help); return command == "help" || command == "--help" || command == "-h" ? 0 : 64
        }
    }

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.x" }

    static let help = """
    slinky — use the secrets in Slinky without putting them in files.

      slinky run [--project NAME] [--env local|preview|production] [--key NAME]… -- COMMAND…
          Run a command with a project's variables (and any keys you name). Slinky asks with Touch ID first.
      slinky env --export [--project NAME] [--env …]     Print export lines for your shell (asks first).
      slinky xcconfig [--project NAME] [--env …] [--out FILE]   Write an .xcconfig for an Xcode build.
      slinky ls                    List names (never values). Slinky must be unlocked.
      slinky check [FOLDER]        Which variables a project still needs.
      slinky request NAME [REASON] Ask Slinky to open Add Item for NAME, so you paste it there.
      slinky guard                 Check staged changes for saved secrets.  slinky guard install  adds a git hook.
      slinky hook zsh|bash         Shell code that loads a linked project's variables when you cd into it.
      slinky notarize-profile NAME [--item KEY]   Save a notarytool profile from an App Store Connect key.
      slinky mcp                   The MCP server for AI agents (names only; they run commands with slinky run).
      slinky status | detect VALUE | version
    """

    // MARK: Talking to the app

    static func send(_ request: Broker.Request, launch: Bool = true) -> Broker.Response {
        var request = request
        let env = ProcessInfo.processInfo.environment
        for key in Broker.agentMarkers where env[key] != nil { request.markers[key] = env[key] }
        guard let fd = connect(launch: launch) else {
            return .fail(launch ? "Couldn't reach Slinky. Open it and try again." : "")
        }
        defer { close(fd) }
        guard let data = try? JSONEncoder().encode(request) else { return .fail("Couldn't send that.") }
        LocalSocket.writeLine(fd, data)
        guard let line = LocalSocket.readLine(fd), let response = try? JSONDecoder().decode(Broker.Response.self, from: line) else {
            return .fail("Slinky didn't answer.")
        }
        return response
    }

    private static func connect(launch: Bool) -> Int32? {
        let path = Broker.socketURL.path
        if let fd = LocalSocket.connect(path) { return fd }
        guard launch else { return nil }
        // Start Slinky in the background (this same app), then wait for it to listen.
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-g", appBundlePath]
        try? open.run()
        open.waitUntilExit()
        for _ in 0..<40 {
            usleep(200_000)
            if let fd = LocalSocket.connect(path) { return fd }
        }
        return nil
    }

    /// …/Slinky.app, from this binary's path (…/Slinky.app/Contents/MacOS/Slinky).
    static var appBundlePath: String {
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        return exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path
    }

    // MARK: Options

    private struct Options {
        var project: String?
        var environment: String?
        var keys: [String] = []
        var out: String?
        var export = false
        var item: String?
        var rest: [String] = []
    }

    private static func parse(_ args: [String]) -> Options? {
        var o = Options()
        var i = 0
        while i < args.count {
            let a = args[i]
            func value() -> String? { i + 1 < args.count ? args[i + 1] : nil }
            switch a {
            case "--": o.rest = Array(args[(i + 1)...]); return o
            case "--project", "-p": guard let v = value() else { return nil }; o.project = v; i += 1
            case "--env", "-e": guard let v = value() else { return nil }; o.environment = v; i += 1
            case "--key", "-k": guard let v = value() else { return nil }; o.keys.append(v); i += 1
            case "--out", "-o": guard let v = value() else { return nil }; o.out = v; i += 1
            case "--item": guard let v = value() else { return nil }; o.item = v; i += 1
            case "--export": o.export = true
            default: o.rest.append(a)
            }
            i += 1
        }
        return o
    }

    private static func fail(_ message: String?, code: Int32 = 1) -> Int32 {
        if let message, !message.isEmpty { FileHandle.standardError.write(Data("slinky: \(message)\n".utf8)) }
        return code
    }

    private static func note(_ response: Broker.Response) {
        if let held = response.withheld, !held.isEmpty {
            FileHandle.standardError.write(Data("slinky: held back from agents: \(held.joined(separator: ", "))\n".utf8))
        }
        if let missing = response.names, !missing.isEmpty {
            FileHandle.standardError.write(Data("slinky: not in Slinky yet: \(missing.joined(separator: ", "))\n".utf8))
        }
    }

    // MARK: Commands

    private static func runCommand(_ args: [String]) -> Int32 {
        guard let o = parse(args), !o.rest.isEmpty else { return fail("usage: slinky run [--project NAME] [--env ENV] -- COMMAND…", code: 64) }
        let r = send(Broker.Request(op: .env, argv: o.rest, purpose: .run, project: o.project, environment: o.environment, keys: o.keys))
        guard r.ok, let env = r.env else { return fail(r.message) }
        note(r)
        for (name, _) in ProcessInfo.processInfo.environment where Broker.isStripped(name) { unsetenv(name) }
        for (name, value) in env where !Broker.isStripped(name) { setenv(name, value, 1) }
        let argv = o.rest.map { strdup($0) } + [nil]
        execvp(o.rest[0], argv)
        return fail("couldn't run \(o.rest[0]): \(String(cString: strerror(errno)))", code: 127)
    }

    private static func envCommand(_ args: [String]) -> Int32 {
        guard let o = parse(args) else { return fail("usage: slinky env --export [--project NAME] [--env ENV]", code: 64) }
        let r = send(Broker.Request(op: .env, purpose: .export, project: o.project, environment: o.environment, keys: o.keys))
        guard r.ok, let env = r.env else { return fail(r.message) }
        note(r)
        print(Broker.shellExports(env))
        return 0
    }

    private static func xcconfigCommand(_ args: [String]) -> Int32 {
        guard let o = parse(args) else { return fail("usage: slinky xcconfig [--project NAME] [--env ENV] [--out FILE]", code: 64) }
        let r = send(Broker.Request(op: .env, purpose: .xcconfig, project: o.project, environment: o.environment, keys: o.keys))
        guard r.ok, let env = r.env else { return fail(r.message) }
        note(r)
        let text = Broker.xcconfig(env, project: r.project ?? o.project ?? "this build")
        if let out = o.out {
            FileManager.default.createFile(atPath: out, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600])
        } else {
            print(text, terminator: "")
        }
        return 0
    }

    private static func listCommand() -> Int32 {
        let r = send(Broker.Request(op: .list))
        guard r.ok else { return fail(r.message) }
        for line in r.lines ?? [] { print(line) }
        return 0
    }

    private static func checkCommand(_ args: [String]) -> Int32 {
        let folder = args.first.map { URL(fileURLWithPath: $0).standardizedFileURL.path } ?? FileManager.default.currentDirectoryPath
        let r = send(Broker.Request(op: .check, text: folder))
        guard r.ok else { return fail(r.message) }
        let missing = r.names ?? []
        print(missing.isEmpty ? "Everything \(r.project ?? "this project") expects is in Slinky." : "Missing: \(missing.joined(separator: ", "))")
        return missing.isEmpty ? 0 : 2
    }

    private static func statusCommand() -> Int32 {
        let r = send(Broker.Request(op: .status), launch: false)
        print(r.ok ? (r.message ?? "") : "Slinky isn't running.")
        return r.ok ? 0 : 1
    }

    private static func projectForDirCommand() -> Int32 {
        // For the shell hook: quiet, fast, never starts Slinky.
        let r = send(Broker.Request(op: .projectForDir), launch: false)
        if r.ok, let p = r.project { print(p); return 0 }
        return 1
    }

    private static func requestCommand(_ args: [String]) -> Int32 {
        guard let name = args.first else { return fail("usage: slinky request NAME [REASON]", code: 64) }
        let r = send(Broker.Request(op: .request, name: name, reason: args.dropFirst().joined(separator: " ")))
        guard r.ok else { return fail(r.message) }
        print("Slinky opened Add Item for \(name). Paste the value there, not here.")
        return 0
    }

    private static func notarizeCommand(_ args: [String]) -> Int32 {
        guard let o = parse(args), let profile = o.rest.first else { return fail("usage: slinky notarize-profile NAME [--item KEY]", code: 64) }
        let r = send(Broker.Request(op: .notarize, name: profile, text: o.item))
        guard r.ok else { return fail(r.message) }
        print(r.message ?? "Done.")
        return 0
    }

    // MARK: Git guard

    private static func guardCommand(_ args: [String]) -> Int32 {
        if args.first == "install" { return installGuard() }
        let diff = Process()
        diff.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        diff.arguments = ["diff", "--cached", "--no-color", "-U0"]
        let pipe = Pipe()
        diff.standardOutput = pipe
        do { try diff.run() } catch { return fail("couldn't read the staged changes.") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        diff.waitUntilExit()
        // Only added lines matter.
        let added = String(decoding: data, as: UTF8.self).split(separator: "\n").filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.joined(separator: "\n")
        guard !added.isEmpty else { return 0 }
        let r = send(Broker.Request(op: .guardDiff, text: added))
        guard r.ok else {
            // Couldn't check (locked, or Slinky isn't there): say so, and don't block the commit.
            FileHandle.standardError.write(Data("slinky: \(r.message ?? "couldn't check this commit"). Committing anyway.\n".utf8))
            return 0
        }
        if let found = r.names, !found.isEmpty {
            FileHandle.standardError.write(Data("""
            slinky: this commit contains secrets saved in Slinky: \(found.joined(separator: ", ")).
                    Take them out (use `slinky run` or a .env.example instead), or commit with --no-verify if you must.

            """.utf8))
            return 1
        }
        return 0
    }

    private static func installGuard() -> Int32 {
        let top = Process()
        top.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        top.arguments = ["rev-parse", "--git-path", "hooks"]
        let pipe = Pipe()
        top.standardOutput = pipe
        do { try top.run() } catch { return fail("this isn't a git repository.") }
        top.waitUntilExit()
        let hooks = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard top.terminationStatus == 0, !hooks.isEmpty else { return fail("this isn't a git repository.") }
        let hook = URL(fileURLWithPath: hooks).appendingPathComponent("pre-commit")
        let line = "slinky guard || exit 1"
        var text = (try? String(contentsOf: hook, encoding: .utf8)) ?? "#!/bin/sh\n"
        if text.contains(line) { print("The Slinky check is already in \(hook.path)."); return 0 }
        text += (text.hasSuffix("\n") ? "" : "\n") + "# Added by Slinky: stop commits that contain secrets saved in Slinky.\n\(line)\n"
        do {
            try FileManager.default.createDirectory(at: hook.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: hook, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        } catch { return fail("couldn't write \(hook.path).") }
        print("Added the Slinky check to \(hook.path).")
        return 0
    }

    // MARK: Shell hook

    private static func hookCommand(_ args: [String]) -> Int32 {
        switch args.first {
        case "zsh":
            print("""
            # Slinky: load a linked project's variables when you cd into it, unload them when you leave.
            _slinky_load() {
              local p; p="$(slinky project-for-dir 2>/dev/null)"
              [[ "$p" == "$_SLINKY_PROJECT" ]] && return
              if [[ -n "$_SLINKY_NAMES" ]]; then for n in ${=_SLINKY_NAMES}; do unset "$n"; done; unset _SLINKY_NAMES; fi
              _SLINKY_PROJECT="$p"
              [[ -n "$p" ]] && eval "$(slinky env --export)"
            }
            autoload -Uz add-zsh-hook
            add-zsh-hook chpwd _slinky_load
            _slinky_load
            """)
        case "bash":
            print("""
            # Slinky: load a linked project's variables when you cd into it, unload them when you leave.
            _slinky_load() {
              local p; p="$(slinky project-for-dir 2>/dev/null)"
              [[ "$p" == "$_SLINKY_PROJECT" ]] && return
              if [[ -n "$_SLINKY_NAMES" ]]; then for n in $_SLINKY_NAMES; do unset "$n"; done; unset _SLINKY_NAMES; fi
              _SLINKY_PROJECT="$p"
              [[ -n "$p" ]] && eval "$(slinky env --export)"
            }
            PROMPT_COMMAND="_slinky_load${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
            """)
        default:
            return fail("usage: slinky hook zsh|bash  (then add  eval \"$(slinky hook zsh)\"  to ~/.zshrc)", code: 64)
        }
        return 0
    }
}
