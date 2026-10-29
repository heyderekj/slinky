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
    /// When the Recovery Key was last made (added in 1.5), so a synced Mac takes the newer one.
    var recoverySet: Date?
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
        var raw = vaultKey.withUnsafeBytes { Data($0) }
        defer { raw.resetBytes(in: 0..<raw.count) }
        let file = VaultFile(enclaveWrappedKey: try enclave.wrap(raw), recoveryWrappedKey: try recovery.wrap(raw),
                             payload: try seal(document, with: vaultKey), saved: .now, recoverySet: .now)
        try write(file)
        return (VaultSession(vaultKey: vaultKey, document: document), recovery)
    }

    /// Touch ID (or password) unlock on this Mac. A vault locked the classic way on a Mac that can do the
    /// post-quantum lock gets wrapped again with it, here, while the key is in hand.
    public func unlock(context: LAContext?) throws -> VaultSession {
        var file = try read()
        var raw = try enclave.unwrap(file.enclaveWrappedKey, context: context)
        defer { raw.resetBytes(in: 0..<raw.count) }
        let vaultKey = Self.key(from: &raw)
        let document = try open(file.payload, with: vaultKey)
        if enclave.needsRewrap(file.enclaveWrappedKey), let rewrapped = try? vaultKey.withUnsafeBytes({ try enclave.wrap(Data($0)) }) {
            file.enclaveWrappedKey = rewrapped
            try write(file)
        }
        return VaultSession(vaultKey: vaultKey, document: document)
    }

    /// Whether this Mac's copy of the vault key is under the post-quantum lock.
    public var usesHybridLock: Bool { (try? read()).map { Envelope.isHybrid($0.enclaveWrappedKey) } ?? false }

    /// A SymmetricKey from raw bytes, zeroing the bytes it came from (macOS 27 does both in one step).
    static func key(from raw: inout Data) -> SymmetricKey {
        if #available(macOS 27, *) {
            var span = raw.mutableBytes
            return SymmetricKey(copyingWithZeroing: &span)
        }
        let key = SymmetricKey(data: raw)
        raw.resetBytes(in: 0..<raw.count)
        return key
    }

    /// Recovery Key unlock: a new Mac, a restored backup, or a reset Secure Enclave.
    /// Re-wraps the vault key for this Mac's enclave so Touch ID works from now on.
    public func unlock(recovery: RecoveryKey) throws -> VaultSession {
        var file = try read()
        var raw = try recovery.unwrap(file.recoveryWrappedKey)
        defer { raw.resetBytes(in: 0..<raw.count) }
        let vaultKey = SymmetricKey(data: raw)
        let document = try open(file.payload, with: vaultKey)
        file.enclaveWrappedKey = try enclave.wrap(raw)
        try write(file)
        return VaultSession(vaultKey: vaultKey, document: document)
    }

    /// Makes a new Recovery Key for an unlocked vault. The old printed key stops working;
    /// Touch ID on this Mac is unchanged. Show the new key to the person exactly once.
    public func replaceRecoveryKey(for session: VaultSession) throws -> RecoveryKey {
        var file = try read()
        let recovery = RecoveryKey.generate()
        var raw = session.vaultKey.withUnsafeBytes { Data($0) }
        defer { raw.resetBytes(in: 0..<raw.count) }
        file.recoveryWrappedKey = try recovery.wrap(raw)
        file.saved = .now
        file.recoverySet = .now
        try write(file)
        return recovery
    }

    // MARK: Backups

    /// Writes a backup of an unlocked vault to `destination`. It's the same encrypted vault, minus this Mac's
    /// Touch ID key, so it opens only with the Recovery Key the vault has right now. No new crypto.
    public func exportBackup(for session: VaultSession, to destination: URL) throws {
        let current = try read()
        let backup = VaultFile(enclaveWrappedKey: Data(), recoveryWrappedKey: current.recoveryWrappedKey,
                               payload: try seal(session.document, with: session.vaultKey), saved: .now)
        try JSONEncoder.vault.encode(backup).write(to: destination, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }

    /// Opens a backup with its Recovery Key and makes it this Mac's vault, wrapped for Touch ID here.
    /// The vault it replaces is kept as `vault.slinky.previous`. Throws `wrongRecoveryKey` without
    /// touching anything if the key doesn't fit.
    public func restoreBackup(from source: URL, recovery: RecoveryKey) throws -> VaultSession {
        let backup = try read(from: source)
        let raw = try recovery.unwrap(backup.recoveryWrappedKey)
        let vaultKey = SymmetricKey(data: raw)
        let document = try open(backup.payload, with: vaultKey)
        let file = VaultFile(enclaveWrappedKey: try enclave.wrap(raw), recoveryWrappedKey: backup.recoveryWrappedKey,
                             payload: backup.payload, saved: .now)
        try write(file)
        return VaultSession(vaultKey: vaultKey, document: document)
    }

    // MARK: Sync

    /// The copy that goes in a sync folder: the same file as a backup (no Touch ID key, so it opens only with the
    /// Recovery Key or on a Mac that already holds the vault key). No new crypto.
    public func syncCopy(for session: VaultSession) throws -> Data {
        let current = try read()
        let copy = VaultFile(enclaveWrappedKey: Data(), recoveryWrappedKey: current.recoveryWrappedKey,
                             payload: try seal(session.document, with: session.vaultKey), saved: .now,
                             recoverySet: current.recoverySet)
        return try JSONEncoder.vault.encode(copy)
    }

    /// Opens a sync copy with this vault's key. nil when it's a different vault (made with another key), which
    /// needs its Recovery Key and `adopt` instead.
    public func openSyncCopy(_ data: Data, session: VaultSession) throws -> VaultDocument? {
        let copy = try decode(data)
        return try? open(copy.payload, with: session.vaultKey)
    }

    /// If the sync copy carries a newer Recovery Key (made on another Mac), this Mac takes it too, so every copy
    /// opens with the same printed key. Returns whether it changed.
    @discardableResult
    public func takeNewerRecoveryKey(from data: Data) throws -> Bool {
        let copy = try decode(data)
        var file = try read()
        guard let theirs = copy.recoverySet, theirs > (file.recoverySet ?? .distantPast),
              copy.recoveryWrappedKey != file.recoveryWrappedKey else { return false }
        file.recoveryWrappedKey = copy.recoveryWrappedKey
        file.recoverySet = theirs
        try write(file)
        return true
    }

    /// Makes a synced vault this Mac's own: opened with its Recovery Key, wrapped for Touch ID here, with this Mac's
    /// items (`merging`) folded in. The vault it replaces is kept as `vault.slinky.previous`, and this Mac's old
    /// Recovery Key stops working. Throws `wrongRecoveryKey` without touching anything if the key doesn't fit.
    public func adopt(syncCopy data: Data, recovery: RecoveryKey, merging local: VaultDocument?) throws -> VaultSession {
        let copy = try decode(data)
        let raw = try recovery.unwrap(copy.recoveryWrappedKey)
        let key = SymmetricKey(data: raw)
        var document = try open(copy.payload, with: key)
        if let local { document = VaultMerge.merge(document, local) }
        let file = VaultFile(enclaveWrappedKey: try enclave.wrap(raw), recoveryWrappedKey: copy.recoveryWrappedKey,
                             payload: try seal(document, with: key), saved: .now, recoverySet: copy.recoverySet)
        try write(file)
        return VaultSession(vaultKey: key, document: document)
    }

    private func decode(_ data: Data) throws -> VaultFile {
        let file: VaultFile
        do { file = try JSONDecoder.vault.decode(VaultFile.self, from: data) }
        catch { throw VaultError.badFormat("not a Slinky vault") }
        guard file.format == "slinky-vault", file.version == 1 else { throw VaultError.badFormat("unknown version \(file.version)") }
        return file
    }

    /// Whether a file is a Slinky vault or backup, without opening it.
    public static func isVaultFile(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), data.count < 64 * 1024 * 1024,
              let file = try? JSONDecoder.vault.decode(VaultFile.self, from: data) else { return false }
        return file.format == "slinky-vault"
    }

    public func save(_ session: VaultSession) throws {
        var file = try read()
        file.payload = try seal(session.document, with: session.vaultKey)
        file.saved = .now
        try write(file)
    }

    // MARK: file I/O

    /// The plaintext JSON is zeroed once it's sealed or decoded. Fewer copies of values in memory, not none:
    /// the document itself holds them while unlocked.
    private func seal(_ document: VaultDocument, with key: SymmetricKey) throws -> Data {
        var json = try JSONEncoder.vault.encode(document)
        defer { json.resetBytes(in: 0..<json.count) }
        return try AES.GCM.seal(json, using: key, authenticating: Self.aad).combined!
    }

    private func open(_ payload: Data, with key: SymmetricKey) throws -> VaultDocument {
        var json: Data
        do { json = try AES.GCM.open(AES.GCM.SealedBox(combined: payload), using: key, authenticating: Self.aad) }
        catch { throw VaultError.badFormat("payload didn't decrypt") }
        defer { json.resetBytes(in: 0..<json.count) }
        return try JSONDecoder.vault.decode(VaultDocument.self, from: json)
    }

    private func read() throws -> VaultFile { try read(from: url) }

    private func read(from url: URL) throws -> VaultFile {
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
