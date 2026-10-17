import CryptoKit
import Foundation
import LocalAuthentication
import SlinkyCoreShared

/// What's on disk. Everything except the format header is encrypted.
struct VaultFile: Codable {
    var format = "slinky-vault"
    var version = 1
    /// The vault key, wrapped by this Mac's Secure Enclave key (Touch ID to open).
    var enclaveWrappedKey: Data
    /// The same vault key, wrapped by the printed Recovery Key.
    var recoveryWrappedKey: Data
    /// AES-GCM (combined) of the JSON VaultDocument.
    var payload: Data
    var saved: Date
}

/// An unlocked vault. Holds the vault key in memory until it's locked (dropped).
public struct VaultSession: Sendable {
    let vaultKey: SymmetricKey
    public var document: VaultDocument
}

public final class VaultStore: @unchecked Sendable {
    public let url: URL
    private let enclave: KeyWrapping
    private static let aad = Data("slinky-vault-v1".utf8)

    public init(url: URL, enclave: KeyWrapping) {
        self.url = url
        self.enclave = enclave
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Slinky/vault.slinky")
    }

    public var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    /// Creates a new vault. Returns the Recovery Key to show the person exactly once.
    public func create(_ document: VaultDocument = VaultDocument()) throws -> (VaultSession, RecoveryKey) {
        let vaultKey = SymmetricKey(size: .bits256)
        let recovery = RecoveryKey.generate()
        let raw = vaultKey.withUnsafeBytes { Data($0) }
        let file = VaultFile(enclaveWrappedKey: try enclave.wrap(raw), recoveryWrappedKey: try recovery.wrap(raw),
                             payload: try seal(document, with: vaultKey), saved: .now)
        try write(file)
        return (VaultSession(vaultKey: vaultKey, document: document), recovery)
    }

    /// Touch ID (or password) unlock on this Mac.
    public func unlock(context: LAContext?) throws -> VaultSession {
        let file = try read()
        let vaultKey = SymmetricKey(data: try enclave.unwrap(file.enclaveWrappedKey, context: context))
        return VaultSession(vaultKey: vaultKey, document: try open(file.payload, with: vaultKey))
    }

    /// Recovery Key unlock: a new Mac, a restored backup, or a reset Secure Enclave.
    /// Re-wraps the vault key for this Mac's enclave so Touch ID works from now on.
    public func unlock(recovery: RecoveryKey) throws -> VaultSession {
        var file = try read()
        let raw = try recovery.unwrap(file.recoveryWrappedKey)
        let vaultKey = SymmetricKey(data: raw)
        let document = try open(file.payload, with: vaultKey)
        file.enclaveWrappedKey = try enclave.wrap(raw)
        try write(file)
        return VaultSession(vaultKey: vaultKey, document: document)
    }

    public func save(_ session: VaultSession) throws {
        var file = try read()
        file.payload = try seal(session.document, with: session.vaultKey)
        file.saved = .now
        try write(file)
    }

    // MARK: file I/O

    private func seal(_ document: VaultDocument, with key: SymmetricKey) throws -> Data {
        let json = try JSONEncoder.vault.encode(document)
        return try AES.GCM.seal(json, using: key, authenticating: Self.aad).combined!
    }

    private func open(_ payload: Data, with key: SymmetricKey) throws -> VaultDocument {
        let json: Data
        do { json = try AES.GCM.open(AES.GCM.SealedBox(combined: payload), using: key, authenticating: Self.aad) }
        catch { throw VaultError.badFormat("payload didn't decrypt") }
        return try JSONDecoder.vault.decode(VaultDocument.self, from: json)
    }

    private func read() throws -> VaultFile {
        guard let data = try? Data(contentsOf: url) else { throw VaultError.notFound }
        let file: VaultFile
        do { file = try JSONDecoder.vault.decode(VaultFile.self, from: data) }
        catch { throw VaultError.badFormat("not a Slinky vault") }
        guard file.format == "slinky-vault", file.version == 1 else { throw VaultError.badFormat("unknown version \(file.version)") }
        return file
    }

    /// Atomic write, 0600, inside a 0700 folder. The previous version is kept as `.previous` in case a write goes wrong.
    private func write(_ file: VaultFile) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let previous = url.appendingPathExtension("previous")
        if fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: previous)
            try? fm.copyItem(at: url, to: previous)
        }
        try JSONEncoder.vault.encode(file).write(to: url, options: [.atomic])
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        if fm.fileExists(atPath: previous.path) { try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: previous.path) }
    }
}

extension JSONEncoder {
    static var vault: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .deferredToDate
        e.outputFormatting = [.sortedKeys]
        return e
    }
}

extension JSONDecoder {
    static var vault: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .deferredToDate
        return d
    }
}
