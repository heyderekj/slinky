import Darwin
import Foundation
import Security
import SlinkyCoreShared

/// Who's on the other end of the socket: the process, and the apps and agents above it.
struct Peer: Sendable {
    let pid: pid_t
    /// Process names from the caller up (slinky, zsh, node, claude, Terminal…).
    let chain: [String]
    /// The app the chain runs inside, if any ("Terminal", "Xcode", "Cursor").
    let app: String?
    /// The AI agent asking, if one is (from the process tree, or the shell's markers as a hint).
    let agent: String?

    var isAgent: Bool { agent != nil }
    /// "Claude Code in Terminal", "Xcode", "Terminal", "You".
    var display: String {
        switch (agent, app) {
        case let (agent?, app?): "\(agent) in \(app)"
        case let (agent?, nil): agent
        case let (nil, app?): app
        default: "You"
        }
    }
}

/// Listens on the local socket for the `slinky` command. Every caller must be signed exactly like Slinky itself
/// (the command is the app's own binary), or it gets nothing. Requests are handed to `handler` on the main actor.
nonisolated final class BrokerServer: @unchecked Sendable {
    typealias Handler = @MainActor @Sendable (Broker.Request, Peer) async -> Broker.Response
    private let handler: Handler
    private var listener: Int32 = -1

    init(handler: @escaping Handler) { self.handler = handler }

    func start() {
        let path = Broker.socketURL.path
        try? FileManager.default.createDirectory(at: Broker.socketURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        guard let fd = LocalSocket.listen(path) else { return }
        listener = fd
        let thread = Thread { [weak self] in self?.acceptLoop() }
        thread.name = "Slinky broker"
        thread.start()
    }

    private func acceptLoop() {
        while true {
            let client = accept(listener, nil, nil)
            if client < 0 { if errno == EINTR { continue } else { return } }
            var timeout = timeval(tv_sec: 300, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            guard Self.isSlinky(client), let line = LocalSocket.readLine(client),
                  let request = try? JSONDecoder().decode(Broker.Request.self, from: line) else {
                LocalSocket.writeLine(client, (try? JSONEncoder().encode(Broker.Response.fail("Only the slinky command can talk to Slinky."))) ?? Data())
                close(client)
                continue
            }
            let peer = Self.peer(client, markers: request.markers)
            let handler = self.handler
            Task { @MainActor in
                let response = await handler(request, peer)
                let data = (try? JSONEncoder().encode(response)) ?? Data()
                Task.detached {
                    LocalSocket.writeLine(client, data)
                    close(client)
                }
            }
        }
    }

    // MARK: Who's asking

    /// The caller's code must satisfy Slinky's own designated requirement: same identifier, same signing identity.
    static func isSlinky(_ fd: Int32) -> Bool {
        var token = audit_token_t()
        var length = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &length) == 0 else { return false }
        let tokenData = Data(bytes: &token, count: MemoryLayout<audit_token_t>.size)
        var guest: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: tokenData] as CFDictionary, [], &guest) == errSecSuccess,
              let guest else { return false }
        var me: SecCode?
        var meStatic: SecStaticCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &meStatic) == errSecSuccess, let meStatic,
              SecCodeCopyDesignatedRequirement(meStatic, [], &requirement) == errSecSuccess else { return false }
        return SecCodeCheckValidity(guest, [], requirement) == errSecSuccess
    }

    static func peer(_ fd: Int32, markers: [String: String]) -> Peer {
        var pid: pid_t = 0
        var length = socklen_t(MemoryLayout<pid_t>.size)
        getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &length)
        var chain: [String] = []
        var app: String?
        var agent: String?
        var current = pid
        for _ in 0..<16 where current > 1 {
            var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let n = proc_pidpath(current, &path, UInt32(path.count))
            let full = n > 0 ? String(cString: path) : ""
            chain.append((full as NSString).lastPathComponent)
            if agent == nil, let name = Broker.agentProcesses[(full as NSString).lastPathComponent.lowercased()] { agent = name }
            if app == nil, let range = full.range(of: ".app/") {
                let appName = ((String(full[..<range.lowerBound]) as NSString).lastPathComponent)
                if appName != "Slinky" { app = appName }
            }
            // Claude Code runs as node with a "claude" script; look at the arguments too.
            if agent == nil, full.hasSuffix("/node"), arguments(of: current).contains(where: { $0.contains("claude-code") || $0.hasSuffix("/claude") }) {
                agent = "Claude Code"
            }
            var info = proc_bsdinfo()
            guard proc_pidinfo(current, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0 else { break }
            current = pid_t(info.pbi_ppid)
        }
        if agent == nil {
            if markers["CLAUDECODE"] != nil || markers["CLAUDE_CODE_ENTRYPOINT"] != nil { agent = "Claude Code" }
            else if markers["CURSOR_AGENT"] != nil { agent = "Cursor" }
            else if markers["CODEX_SANDBOX"] != nil || markers["CODEX_SANDBOX_NETWORK_DISABLED"] != nil { agent = "Codex" }
            else if markers["GEMINI_CLI"] != nil { agent = "Gemini CLI" }
        }
        return Peer(pid: pid, chain: chain, app: app, agent: agent)
    }

    /// A process's arguments (KERN_PROCARGS2), for telling Claude Code's node apart from any other.
    private static func arguments(of pid: pid_t) -> [String] {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }
        let parts = buffer[4..<size].split(separator: 0, omittingEmptySubsequences: true)
        return parts.prefix(6).map { String(decoding: $0, as: UTF8.self) }
    }
}
