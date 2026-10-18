import Darwin
import Foundation

/// A Unix-domain socket, one JSON line each way. Used by the app (listening) and the `slinky` command (asking).
/// It lives next to the vault in a folder only you can open, and the app checks every caller's code signature.
nonisolated enum LocalSocket {
    static let maxLine = 16 * 1024 * 1024

    private static func address(_ path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return addr
    }

    static func connect(_ path: String) -> Int32? {
        guard var addr = address(path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if ok != 0 { close(fd); return nil }
        return fd
    }

    /// Binds a fresh socket (removing a stale one), readable and writable by this user only.
    static func listen(_ path: String) -> Int32? {
        unlink(path)
        guard var addr = address(path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, Darwin.listen(fd, 16) == 0 else { close(fd); return nil }
        return fd
    }

    static func readLine(_ fd: Int32) -> Data? {
        var out = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { return out.isEmpty ? nil : out }
            if let nl = buffer[0..<n].firstIndex(of: 10) {
                out.append(contentsOf: buffer[0..<nl])
                return out
            }
            out.append(contentsOf: buffer[0..<n])
            if out.count > maxLine { return nil }
        }
    }

    static func writeLine(_ fd: Int32, _ data: Data) {
        var payload = data
        payload.append(10)
        payload.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if n <= 0 { return }
                offset += n
            }
        }
    }
}
