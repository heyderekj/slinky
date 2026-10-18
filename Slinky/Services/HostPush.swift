import Foundation

/// Sending a project's variables to where the app runs, through that host's own command-line tool.
/// Values go in on stdin (or, for Netlify, a 0600 temp file deleted straight after), never in arguments,
/// so they don't show up in `ps`. Nothing is sent until the person has seen the list and said yes.
nonisolated enum HostPush {
    enum Host: String, CaseIterable, Identifiable, Sendable {
        case vercel, netlify, workers, pages, fly
        var id: String { rawValue }

        var title: String {
            switch self {
            case .vercel: "Vercel"
            case .netlify: "Netlify"
            case .workers: "Cloudflare Workers"
            case .pages: "Cloudflare Pages"
            case .fly: "Fly.io"
            }
        }

        /// The tool that has to be installed (and signed in).
        var tool: String {
            switch self {
            case .vercel: "vercel"
            case .netlify: "netlify"
            case .workers, .pages: "wrangler"
            case .fly: "fly"
            }
        }

        /// Whether it needs a name typed in (Pages project, Fly app). Vercel, Netlify and Workers read the folder.
        var targetLabel: String? {
            switch self {
            case .pages: "Pages project"
            case .fly: "Fly app"
            default: nil
            }
        }

        var canCompare: Bool { self != .netlify }   // Netlify's list prints values; Slinky doesn't read those.
    }

    struct Result: Sendable {
        var sent: [String] = []
        var failed: [String: String] = [:]
    }

    /// Vercel's environments for Slinky's.
    static func vercelTarget(_ environment: String) -> String {
        switch environment {
        case "production": "production"
        case "preview": "preview"
        default: "development"
        }
    }

    /// The tool's full path, found the way Terminal would (login shell PATH).
    static func toolPath(_ tool: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", #"command -v -- "$0""#, tool]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let path = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return p.terminationStatus == 0 && path.hasPrefix("/") ? path : nil
    }

    /// Fly reads app = "name" from fly.toml.
    static func flyApp(in folder: String) -> String? {
        guard let text = try? String(contentsOf: URL(fileURLWithPath: folder).appendingPathComponent("fly.toml"), encoding: .utf8),
              let range = text.range(of: #"(?m)^app\s*=\s*["']([^"']+)["']"#, options: .regularExpression) else { return nil }
        return text[range].split(separator: "=").last.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }
    }

    /// The arguments for setting one variable. Never contains the value (tests check that).
    static func arguments(_ host: Host, name: String, environment: String, target: String?) -> [String] {
        switch host {
        case .vercel: ["env", "add", name, vercelTarget(environment), "--force"]
        case .workers: ["secret", "put", name]
        case .pages: ["pages", "secret", "put", name, "--project-name", target ?? ""]
        case .fly: ["secrets", "import", "-a", target ?? ""]
        case .netlify: ["env:import", "--replace-existing"]
        }
    }

    static func send(_ host: Host, values: [String: String], environment: String, folder: String, target: String?) -> Result {
        var result = Result()
        guard let tool = toolPath(host.tool) else {
            result.failed["*"] = "\(host.tool) isn't installed. Install it and sign in, then try again."
            return result
        }
        switch host {
        case .fly:
            // One import, NAME=value lines on stdin.
            let body = values.keys.sorted().map { "\($0)=\(values[$0]!)" }.joined(separator: "\n") + "\n"
            let (status, output) = run(tool, arguments(host, name: "", environment: environment, target: target), stdin: body, folder: folder)
            if status == 0 { result.sent = values.keys.sorted() } else { result.failed["*"] = output }
        case .netlify:
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("slinky-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: dir) }
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let file = dir.appendingPathComponent(".env")
                let body = values.keys.sorted().map { "\($0)=\(quoted(values[$0]!))" }.joined(separator: "\n") + "\n"
                FileManager.default.createFile(atPath: file.path, contents: Data(body.utf8), attributes: [.posixPermissions: 0o600])
                let (status, output) = run(tool, ["env:import", file.path, "--replace-existing"], stdin: nil, folder: folder)
                if status == 0 { result.sent = values.keys.sorted() } else { result.failed["*"] = output }
            } catch {
                result.failed["*"] = "Couldn't make a private temp file."
            }
        default:
            for name in values.keys.sorted() {
                let (status, output) = run(tool, arguments(host, name: name, environment: environment, target: target), stdin: values[name]!, folder: folder)
                if status == 0 { result.sent.append(name) } else { result.failed[name] = output }
            }
        }
        return result
    }

    /// Names the host has (never values).
    static func remoteNames(_ host: Host, environment: String, folder: String, target: String?) -> Set<String>? {
        guard host.canCompare, let tool = toolPath(host.tool) else { return nil }
        let args: [String]
        switch host {
        case .vercel: args = ["env", "ls", vercelTarget(environment)]
        case .workers: args = ["secret", "list"]
        case .pages: args = ["pages", "secret", "list", "--project-name", target ?? ""]
        case .fly: args = ["secrets", "list", "-a", target ?? "", "--json"]
        case .netlify: return nil
        }
        let (status, output) = run(tool, args, stdin: nil, folder: folder)
        guard status == 0 else { return nil }
        // Pull out what look like variable names; values and digests are never kept.
        if let data = output.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return Set(json.compactMap { ($0["name"] ?? $0["Name"]) as? String })
        }
        var names = Set<String>()
        for line in output.split(separator: "\n") {
            for word in line.split(whereSeparator: { $0 == " " || $0 == ":" || $0 == "\t" }) {
                let w = word.trimmingCharacters(in: CharacterSet(charactersIn: "-:│|"))
                if w.count > 1, w.range(of: #"^[A-Z][A-Z0-9_]*$"#, options: .regularExpression) != nil { names.insert(w); break }
            }
        }
        return names
    }

    private static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") + "\""
    }

    private static func run(_ tool: String, _ args: [String], stdin: String?, folder: String) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: folder)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (URL(fileURLWithPath: tool).deletingLastPathComponent().path) + ":/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        env["CI"] = "1"   // No interactive prompts.
        p.environment = env
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = output
        do { try p.run() } catch { return (-1, "Couldn't run \(tool).") }
        if let stdin { input.fileHandleForWriting.write(Data(stdin.utf8)) }
        try? input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        return (p.terminationStatus, String(text.suffix(600)))
    }
}
