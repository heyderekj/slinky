import Foundation
import SlinkyCoreShared

/// `slinky mcp`: a Model Context Protocol server over stdio (newline-delimited JSON-RPC) for AI agents.
/// Names only. No tool returns a value or anything derived from one. To use a secret, an agent runs its
/// command through `slinky run -- …` in its own shell, where the person approves it with Touch ID.
nonisolated enum MCPServer {
    static let instructions = """
    Slinky keeps this person's API keys and .env variables out of files. You never see the values.
    • To run something that needs secrets, run it in your shell as: slinky run -- <command> (for example: slinky run -- npm run dev). \
    The person approves it with Touch ID. Use --env preview or --env production for those environments.
    • Never ask the person to paste a key into the chat. If a variable is missing, call request_secret: Slinky opens a window \
    where they paste it.
    • Don't read or write .env files with real values. Write .env.example with names only.
    """

    nonisolated(unsafe) static let tools: [[String: Any]] = [
        ["name": "list_secrets",
         "description": "List the names of keys and project variables saved in Slinky (never values), whether they're live, and whether agents may use them.",
         "inputSchema": ["type": "object", "properties": [String: Any]()]],
        ["name": "check_env",
         "description": "Which variables a project folder expects (from .env.example) that Slinky doesn't have yet.",
         "inputSchema": ["type": "object", "properties": ["path": ["type": "string", "description": "The project folder. Defaults to the current folder."]]]],
        ["name": "request_secret",
         "description": "Ask the person to add a missing secret. Slinky opens a window with the name filled in; they paste the value there, never in the chat. Returns only whether the window opened.",
         "inputSchema": ["type": "object", "required": ["name"], "properties": [
            "name": ["type": "string", "description": "The variable name, like RESEND_API_KEY."],
            "reason": ["type": "string", "description": "One short line on why it's needed. Shown to the person as coming from you."]]]],
        ["name": "describe_policy",
         "description": "How Slinky lets agents use secrets, and what it never allows.",
         "inputSchema": ["type": "object", "properties": [String: Any]()]],
    ]

    static let policy = """
    • Run commands with secrets as: slinky run -- <command>. Each run is approved by the person with Touch ID, showing your command.
    • Live keys and anything marked "never for agents" are held back from agent runs.
    • Shells, inline code (node -e, python -c), env/printenv, curl/wget/ssh, git push and publishing can't be run with secrets by an agent.
    • No tool here returns a value, a hash, a length or a prefix of one.
    """

    static func run(send: (Broker.Request) -> Broker.Response) -> Int32 {
        while let line = readLine(strippingNewline: true) {
            guard let data = line.data(using: .utf8),
                  let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let id = message["id"]
            let method = message["method"] as? String ?? ""
            let params = message["params"] as? [String: Any] ?? [:]
            guard id != nil else { continue }   // Notifications (like notifications/initialized) need no answer.
            switch method {
            case "initialize":
                reply(id, result: [
                    "protocolVersion": (params["protocolVersion"] as? String) ?? "2025-06-18",
                    "capabilities": ["tools": [String: Any]()],
                    "serverInfo": ["name": "slinky", "version": Command.version],
                    "instructions": instructions,
                ])
            case "ping": reply(id, result: [:])
            case "tools/list": reply(id, result: ["tools": tools])
            case "tools/call":
                let name = params["name"] as? String ?? ""
                let args = params["arguments"] as? [String: Any] ?? [:]
                let (text, isError) = call(name, args, send: send)
                reply(id, result: ["content": [["type": "text", "text": text]], "isError": isError])
            default:
                reply(id, error: ["code": -32601, "message": "Unknown method \(method)"])
            }
        }
        return 0
    }

    private static func call(_ name: String, _ args: [String: Any], send: (Broker.Request) -> Broker.Response) -> (String, Bool) {
        switch name {
        case "list_secrets":
            let r = send(Broker.Request(op: .list))
            guard r.ok else { return (r.message ?? "Slinky is locked.", true) }
            let lines = (r.lines ?? []).map { $0.split(separator: "\t", omittingEmptySubsequences: false).filter { !$0.isEmpty }.joined(separator: " · ") }
            return (lines.isEmpty ? "Nothing saved yet." : lines.joined(separator: "\n"), false)
        case "check_env":
            let path = (args["path"] as? String).map { URL(fileURLWithPath: $0).standardizedFileURL.path } ?? FileManager.default.currentDirectoryPath
            let r = send(Broker.Request(op: .check, text: path))
            guard r.ok else { return (r.message ?? "Couldn't check.", true) }
            let missing = r.names ?? []
            return (missing.isEmpty ? "Slinky has everything this project expects." : "Missing from Slinky: \(missing.joined(separator: ", ")). Call request_secret for each.", false)
        case "request_secret":
            guard let secret = args["name"] as? String else { return ("Give a name.", true) }
            let r = send(Broker.Request(op: .request, name: secret, reason: args["reason"] as? String))
            return (r.ok ? "prompted: Slinky asked the person to add \(secret). Wait for them, then use slinky run." : (r.message ?? "declined"), !r.ok)
        case "describe_policy":
            return (policy, false)
        default:
            return ("Unknown tool \(name).", true)
        }
    }

    private static func reply(_ id: Any?, result: [String: Any]? = nil, error: [String: Any]? = nil) {
        var message: [String: Any] = ["jsonrpc": "2.0", "id": id ?? NSNull()]
        if let result { message["result"] = result }
        if let error { message["error"] = error }
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
