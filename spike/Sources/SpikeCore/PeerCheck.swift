import Darwin
import Foundation
import Security

public struct PeerInfo: Sendable {
    public var pid: pid_t
    public var signatureOK: Bool
    public var signatureDetail: String
    public var chain: [ProcessChain.Link]

    public var chainText: String { chain.map(\.name).reversed().joined(separator: " › ") }
}

/// Who is on the other end of a Unix socket, and is it really our CLI?
public enum PeerCheck {
    /// Our CLI, signed with Derek's Apple Development identity (team B3U6BXA8KP).
    public static let requirement =
        #"identifier "com.slinky.spike.cli" and anchor apple generic and certificate leaf[subject.OU] = "B3U6BXA8KP""#

    private static let SOL_LOCAL_: Int32 = 0
    private static let LOCAL_PEERPID_: Int32 = 0x002
    private static let LOCAL_PEERTOKEN_: Int32 = 0x006

    public static func inspect(fd: Int32) -> PeerInfo {
        var pid: pid_t = 0
        var pidLen = socklen_t(MemoryLayout<pid_t>.size)
        getsockopt(fd, SOL_LOCAL_, LOCAL_PEERPID_, &pid, &pidLen)

        var token = audit_token_t()
        var tokenLen = socklen_t(MemoryLayout<audit_token_t>.size)
        let gotToken = getsockopt(fd, SOL_LOCAL_, LOCAL_PEERTOKEN_, &token, &tokenLen) == 0

        let (ok, detail) = gotToken ? check(token: token) : (false, "no audit token (errno \(errno))")
        return PeerInfo(pid: pid, signatureOK: ok, signatureDetail: detail, chain: ProcessChain.walk(from: pid))
    }

    public static func check(token: audit_token_t) -> (Bool, String) {
        var tokenCopy = token
        let tokenData = Data(bytes: &tokenCopy, count: MemoryLayout<audit_token_t>.size)
        var code: SecCode?
        var status = SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: tokenData] as CFDictionary, [], &code)
        guard status == errSecSuccess, let code else { return (false, "SecCodeCopyGuestWithAttributes \(status)") }

        var req: SecRequirement?
        status = SecRequirementCreateWithString(requirement as CFString, [], &req)
        guard status == errSecSuccess, let req else { return (false, "bad requirement \(status)") }

        status = SecCodeCheckValidity(code, [], req)
        let who = signingSummary(code)
        if status == errSecSuccess { return (true, "valid: \(who)") }
        return (false, "rejected (\(status)): \(who)")
    }

    private static func signingSummary(_ code: SecCode) -> String {
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return "unknown signer" }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return "unsigned" }
        let ident = dict[kSecCodeInfoIdentifier as String] as? String ?? "?"
        let team = dict[kSecCodeInfoTeamIdentifier as String] as? String ?? "no team (ad-hoc)"
        return "\(ident), team \(team)"
    }
}

/// Walks parent processes so an approval card can say "claude › zsh › slinky-spike".
public enum ProcessChain {
    public struct Link: Sendable {
        public var pid: pid_t
        public var name: String
        public var path: String
    }

    public static func walk(from start: pid_t, maxDepth: Int = 12) -> [Link] {
        var links: [Link] = []
        var pid = start
        for _ in 0..<maxDepth {
            guard pid > 1 else { break }
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { break }
            var pathBuf = [CChar](repeating: 0, count: 4096)
            let path = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count)) > 0 ? String(cString: pathBuf) : ""
            let name = path.isEmpty ? withUnsafeBytes(of: info.pbi_name) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
                                    : (path as NSString).lastPathComponent
            links.append(Link(pid: pid, name: name, path: path))
            pid = pid_t(info.pbi_ppid)
        }
        return links
    }
}
