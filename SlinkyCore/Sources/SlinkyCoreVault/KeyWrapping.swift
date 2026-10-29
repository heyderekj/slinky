import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Wraps and unwraps the vault key. The Secure Enclave wrapper asks for Touch ID (or the Mac password) to unwrap.
public protocol KeyWrapping: Sendable {
    func wrap(_ secret: Data) throws -> Data
    func unwrap(_ blob: Data, context: LAContext?) throws -> Data
    /// Whether a blob this wrapper opened should be wrapped again (an older, weaker lock than it would make now).
    func needsRewrap(_ blob: Data) -> Bool
}

extension KeyWrapping {
    public func needsRewrap(_ blob: Data) -> Bool { false }
}

public enum VaultError: Error, Equatable, CustomStringConvertible {
    case keychain(OSStatus, String)
    case accessControl
    case noEnclaveKey
    case badFormat(String)
    case wrongRecoveryKey
    case notFound

    public var description: String {
        switch self {
        case let .keychain(status, op):
            "\(op) failed (OSStatus \(status): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown"))"
        case .accessControl: "Couldn't set up Touch ID protection for the vault key."
        case .noEnclaveKey: "This Mac doesn't have Slinky's vault key yet. Unlock with your Recovery Key."
        case let .badFormat(why): "The vault file isn't readable: \(why)"
        case .wrongRecoveryKey: "That Recovery Key doesn't open this vault."
        case .notFound: "No vault yet."
        }
    }
}

/// Who an envelope is sealed to: a P-256 key, plus an ML-KEM-768 key on Macs that have one (macOS 26 and later).
public struct EnvelopeRecipient: Sendable {
    public let agreement: P256.KeyAgreement.PublicKey
    /// ML-KEM-768 public key, raw. nil for a Mac before macOS 26.
    public let kem: Data?

    public init(agreement: P256.KeyAgreement.PublicKey, kem: Data?) {
        self.agreement = agreement
        self.kem = kem
    }
}

/// Seals small secrets (keys, not documents) to a recipient.
/// - Classic: ephemeral P-256 ECDH + HKDF-SHA256 + AES-GCM.
///   Layout: [65-byte ephemeral public key (starts 0x04)][AES-GCM combined box].
/// - Hybrid (macOS 26+, when the recipient has an ML-KEM key): the P-256 secret and an ML-KEM-768 secret both go
///   into HKDF, so the envelope holds unless both are broken.
///   Layout: [0x48 'H'][version 1][65-byte ephemeral key][1088-byte ML-KEM ciphertext][AES-GCM combined box].
enum Envelope {
    static let info = Data("slinky-vault-key-v1".utf8)
    static let hybridInfo = Data("slinky-hybrid-v1".utf8)
    static let hybridTag: UInt8 = 0x48
    static let kemCiphertextCount = 1088

    static func isHybrid(_ blob: Data) -> Bool { blob.first == hybridTag }

    static func seal(_ secret: Data, to recipient: P256.KeyAgreement.PublicKey) throws -> Data {
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let key = try derive(ephemeral.sharedSecretFromKeyAgreement(with: recipient), salt: ephemeral.publicKey.x963Representation)
        var out = ephemeral.publicKey.x963Representation
        out.append(try AES.GCM.seal(secret, using: key).combined!)
        return out
    }

    /// Hybrid when the recipient has an ML-KEM key and this Mac can use it; classic otherwise.
    static func seal(_ secret: Data, to recipient: EnvelopeRecipient) throws -> Data {
        guard #available(macOS 26, *), let kemRaw = recipient.kem else { return try seal(secret, to: recipient.agreement) }
        let kem = try MLKEM768.PublicKey(rawRepresentation: kemRaw).encapsulate()
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let ecdh = try ephemeral.sharedSecretFromKeyAgreement(with: recipient.agreement)
        let key = hybridKey(ecdh: ecdh, kem: kem.sharedSecret, ephemeral: ephemeral.publicKey.x963Representation,
                            ciphertext: kem.encapsulated, recipient: recipient)
        var out = Data([hybridTag, 1])
        out.append(ephemeral.publicKey.x963Representation)
        out.append(kem.encapsulated)
        out.append(try AES.GCM.seal(secret, using: key).combined!)
        return out
    }

    static func open(_ blob: Data, agreement: (P256.KeyAgreement.PublicKey) throws -> SharedSecret) throws -> Data {
        guard !isHybrid(blob) else { throw VaultError.badFormat("this key needs a newer Mac") }
        guard blob.count > 65 + 28 else { throw VaultError.badFormat("wrapped key too short") }
        let ephemeral = try P256.KeyAgreement.PublicKey(x963Representation: blob.prefix(65))
        let key = try derive(agreement(ephemeral), salt: ephemeral.x963Representation)
        return try AES.GCM.open(AES.GCM.SealedBox(combined: blob.dropFirst(65)), using: key)
    }

    /// Opens either kind. `decapsulate` is only called for a hybrid envelope.
    static func open(_ blob: Data, recipient: EnvelopeRecipient,
                     agreement: (P256.KeyAgreement.PublicKey) throws -> SharedSecret,
                     decapsulate: (Data) throws -> SymmetricKey) throws -> Data {
        guard isHybrid(blob) else { return try open(blob, agreement: agreement) }
        let blob = Data(blob)   // index from 0
        let header = 2, kemStart = header + 65, boxStart = kemStart + kemCiphertextCount
        guard blob.count > boxStart + 28, blob[1] == 1 else { throw VaultError.badFormat("unknown envelope") }
        let ephemeralRaw = blob[header..<kemStart]
        let ciphertext = blob[kemStart..<boxStart]
        let ephemeral = try P256.KeyAgreement.PublicKey(x963Representation: ephemeralRaw)
        let key = hybridKey(ecdh: try agreement(ephemeral), kem: try decapsulate(Data(ciphertext)),
                            ephemeral: Data(ephemeralRaw), ciphertext: Data(ciphertext), recipient: recipient)
        return try AES.GCM.open(AES.GCM.SealedBox(combined: blob[boxStart...]), using: key)
    }

    private static func derive(_ shared: SharedSecret, salt: Data) -> SymmetricKey {
        shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: info, outputByteCount: 32)
    }

    /// Both secrets in, bound to the ciphertexts and the recipient's public keys.
    private static func hybridKey(ecdh: SharedSecret, kem: SymmetricKey, ephemeral: Data, ciphertext: Data,
                                  recipient: EnvelopeRecipient) -> SymmetricKey {
        var ikm = ecdh.withUnsafeBytes { Data($0) }
        kem.withUnsafeBytes { ikm.append(contentsOf: $0) }
        defer { ikm.resetBytes(in: 0..<ikm.count) }
        var bound = hybridInfo
        bound.append(recipient.agreement.x963Representation)
        bound.append(recipient.kem ?? Data())
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: ikm), salt: ephemeral + ciphertext,
                                      info: bound, outputByteCount: 32)
    }
}

/// One opaque Secure Enclave key blob in the login keychain, in an item only Slinky's signing identity can read silently.
struct KeychainBlob: Sendable {
    let service: String
    let account: String
    let label: String

    var exists: Bool { (try? load()) != nil }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func store(_ blob: Data) throws {
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = blob
        add[kSecAttrLabel as String] = label
        add[kSecAttrDescription as String] = "Only usable on this Mac, with Touch ID or your password."
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.keychain(status, "Saving \(label)") }
    }

    func load() throws -> Data {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { throw VaultError.noEnclaveKey }
        guard status == errSecSuccess, let data = out as? Data else { throw VaultError.keychain(status, "Reading \(label)") }
        return data
    }

    func delete() { SecItemDelete(query as CFDictionary) }

    /// Touch ID (or password) and user presence: what every Slinky Secure Enclave key asks for.
    static func presenceAccess() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .userPresence], &error
        ) else { throw VaultError.accessControl }
        return access
    }

    /// Usable by Slinky without asking each time (signing every save to a shared project). Still in the Secure
    /// Enclave, still this Mac only, and the blob is readable silently only by Slinky.
    static func silentAccess() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage], &error
        ) else { throw VaultError.accessControl }
        return access
    }
}

extension LAContext {
    /// Asks once, so several Secure Enclave keys used with this context don't each ask. Call off the main thread.
    func askOnce() throws {
        var error: NSError?
        guard canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { throw error ?? VaultError.accessControl }
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var failure: Error?
        evaluatePolicy(.deviceOwnerAuthentication, localizedReason: localizedReason.isEmpty ? "unlock your vault" : localizedReason) { ok, err in
            if !ok { failure = err ?? VaultError.accessControl }
            done.signal()
        }
        done.wait()
        if let failure { throw failure }
    }
}

/// The real thing: Secure Enclave keys that need user presence to use. A P-256 key on every Mac, plus an ML-KEM-768
/// key on macOS 26 and later, so the vault key's lock also holds against a future quantum computer.
public final class EnclaveWrapper: KeyWrapping, @unchecked Sendable {
    public let service: String
    public let account: String
    private let p256: KeychainBlob
    private let kem: KeychainBlob

    public init(service: String = "com.slinky.app", account: String = "vault-enclave-key") {
        self.service = service
        self.account = account
        p256 = KeychainBlob(service: service, account: account, label: "Slinky vault key (Secure Enclave)")
        kem = KeychainBlob(service: service, account: account.replacingOccurrences(of: "-key", with: "") + "-kem",
                           label: "Slinky vault key, post-quantum (Secure Enclave)")
    }

    public var hasKey: Bool { p256.exists }

    /// Creates the enclave keys this Mac doesn't have yet. Creating needs no Touch ID; using them does.
    public func ensureKey() throws {
        if !p256.exists {
            let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(compactRepresentable: false, accessControl: KeychainBlob.presenceAccess())
            try p256.store(key.dataRepresentation)
        }
        if #available(macOS 26, *), !kem.exists {
            // Some Macs' Secure Enclaves may not do ML-KEM; the P-256 lock still works on its own.
            if let key = try? SecureEnclave.MLKEM768.PrivateKey(accessControl: KeychainBlob.presenceAccess()) {
                try kem.store(key.dataRepresentation)
            }
        }
    }

    public func wrap(_ secret: Data) throws -> Data {
        try ensureKey()
        return try Envelope.seal(secret, to: recipient())
    }

    public func unwrap(_ blob: Data, context: LAContext?) throws -> Data {
        guard Envelope.isHybrid(blob) else {
            let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: p256.load(), authenticationContext: context)
            return try Envelope.open(blob) { try key.sharedSecretFromKeyAgreement(with: $0) }
        }
        guard #available(macOS 26, *) else { throw VaultError.badFormat("this vault was locked on a newer macOS") }
        // Two Secure Enclave keys, one Touch ID.
        try context?.askOnce()
        let agreement = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: p256.load(), authenticationContext: context)
        let decap = try SecureEnclave.MLKEM768.PrivateKey(dataRepresentation: kem.load(), authenticationContext: context)
        let recipient = EnvelopeRecipient(agreement: agreement.publicKey, kem: decap.publicKey.rawRepresentation)
        return try Envelope.open(blob, recipient: recipient,
                                 agreement: { try agreement.sharedSecretFromKeyAgreement(with: $0) },
                                 decapsulate: { try decap.decapsulate($0) })
    }

    /// A classic blob on a Mac that can do the hybrid lock.
    public func needsRewrap(_ blob: Data) -> Bool {
        guard #available(macOS 26, *), !Envelope.isHybrid(blob) else { return false }
        try? ensureKey()
        return kem.exists
    }

    /// Forgets this Mac's enclave keys. The vault still opens with the Recovery Key.
    public func deleteKey() {
        p256.delete()
        kem.delete()
    }

    private func recipient() throws -> EnvelopeRecipient {
        let agreement = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: p256.load())
        var kemPublic: Data?
        if #available(macOS 26, *), let blob = try? kem.load() {
            kemPublic = try SecureEnclave.MLKEM768.PrivateKey(dataRepresentation: blob).publicKey.rawRepresentation
        }
        return EnvelopeRecipient(agreement: agreement.publicKey, kem: kemPublic)
    }
}

/// Software stand-in for tests. Never used by the app. `hybrid` adds an ML-KEM-768 key, like a macOS 26 Mac.
public final class SoftwareWrapper: KeyWrapping, @unchecked Sendable {
    private let key = P256.KeyAgreement.PrivateKey()
    private var kemSeed: Data?
    public var hybrid: Bool { kemSeed != nil }

    public init(hybrid: Bool = false) {
        if hybrid { addKEM() }
    }

    /// Like updating a Mac to macOS 26: it gains an ML-KEM key and keeps its P-256 one.
    public func addKEM() {
        if #available(macOS 26, *), kemSeed == nil { kemSeed = try? MLKEM768.PrivateKey().seedRepresentation }
    }

    public func wrap(_ secret: Data) throws -> Data {
        guard #available(macOS 26, *), let kem = try kemKey() else { return try Envelope.seal(secret, to: key.publicKey) }
        return try Envelope.seal(secret, to: EnvelopeRecipient(agreement: key.publicKey, kem: kem.publicKey.rawRepresentation))
    }

    public func unwrap(_ blob: Data, context: LAContext?) throws -> Data {
        guard Envelope.isHybrid(blob) else { return try Envelope.open(blob) { try key.sharedSecretFromKeyAgreement(with: $0) } }
        guard #available(macOS 26, *), let kem = try kemKey() else { throw VaultError.noEnclaveKey }
        return try Envelope.open(blob, recipient: EnvelopeRecipient(agreement: key.publicKey, kem: kem.publicKey.rawRepresentation),
                                 agreement: { try key.sharedSecretFromKeyAgreement(with: $0) },
                                 decapsulate: { try kem.decapsulate($0) })
    }

    public func needsRewrap(_ blob: Data) -> Bool { hybrid && !Envelope.isHybrid(blob) }

    @available(macOS 26, *)
    private func kemKey() throws -> MLKEM768.PrivateKey? {
        try kemSeed.map { try MLKEM768.PrivateKey(seedRepresentation: $0, publicKey: nil) }
    }
}
