import Darwin
import Foundation

/// A tiny line-based Unix socket server and client. One request line in, one response line out.
public final class SocketServer {
    public typealias Handler = (_ request: String, _ peer: PeerInfo) -> String
    private let path: String
    private var fd: Int32 = -1

    public init(path: URL) { self.path = path.path }

    public func start(handler: @escaping Handler) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        chmod(dir, 0o700)
        unlink(path)

        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        var addr = Self.address(path)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 8) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        chmod(path, 0o600)

        let listenFD = fd
        Thread.detachNewThread {
            while true {
                let client = accept(listenFD, nil, nil)
                if client < 0 { continue }
                let peer = PeerCheck.inspect(fd: client)
                let request = Self.readLine(client)
                let response = handler(request, peer)
                Self.writeLine(client, response)
                close(client)
            }
        }
    }

    static func address(_ path: String) -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        path.withCString { cs in
            withUnsafeMutablePointer(to: &addr.sun_path) {
                $0.withMemoryRebound(to: CChar.self, capacity: capacity) { _ = strncpy($0, cs, capacity - 1) }
            }
        }
        return addr
    }

    static func readLine(_ fd: Int32) -> String {
        var data = Data()
        var byte: UInt8 = 0
        while read(fd, &byte, 1) == 1 {
            if byte == 0x0A { break }
            data.append(byte)
            if data.count > 64 * 1024 { break }
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func writeLine(_ fd: Int32, _ text: String) {
        let bytes = Array((text + "\n").utf8)
        _ = bytes.withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
    }
}

public enum SocketClient {
    public static func send(_ request: String, to path: URL) throws -> String {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        var addr = SocketServer.address(path.path)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw POSIXError(.init(rawValue: errno) ?? .ECONNREFUSED) }
        SocketServer.writeLine(fd, request)
        return SocketServer.readLine(fd)
    }
}
