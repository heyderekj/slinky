import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Wraps and unwraps the vault key. The Secure Enclave wrapper asks for Touch ID (or the Mac password) to unwrap.
public protocol KeyWrapping: Sendable {
    func wrap(_ secret: Data) throws -> Data
    func unwrap(_ blob: Data, context: LAContext?) throws -> Data
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

/// Elliptic-curve envelope: ephemeral P-256 ECDH + HKDF-SHA256 + AES-GCM.
/// Layout: [65-byte ephemeral public key][AES-GCM combined box].
enum Envelope {
    static let info = Data("slinky-vault-key-v1".utf8)

    static func seal(_ secret: Data, to recipient: P256.KeyAgreement.PublicKey) throws -> Data {
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let key = try derive(ephemeral.sharedSecretFromKeyAgreement(with: recipient), salt: ephemeral.publicKey.x963Representation)
        var out = ephemeral.publicKey.x963Representation
        out.append(try AES.GCM.seal(secret, using: key).combined!)
        return out
    }

    static func open(_ blob: Data, agreement: (P256.KeyAgreement.PublicKey) throws -> SharedSecret) throws -> Data {
        guard blob.count > 65 + 28 else { throw VaultError.badFormat("wrapped key too short") }
        let ephemeral = try P256.KeyAgreement.PublicKey(x963Representation: blob.prefix(65))
        let key = try derive(agreement(ephemeral), salt: ephemeral.x963Representation)
        return try AES.GCM.open(AES.GCM.SealedBox(combined: blob.dropFirst(65)), using: key)
    }

    private static func derive(_ shared: SharedSecret, salt: Data) -> SymmetricKey {
        shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: info, outputByteCount: 32)
    }
}

/// The real thing: a Secure Enclave key that needs user presence to use.
/// Its opaque blob lives in the login keychain, in an item only Slinky's signing identity can read silently.
public final class EnclaveWrapper: KeyWrapping, @unchecked Sendable {
    public let service: String
    public let account: String

    public init(service: String = "com.slinky.app", account: String = "vault-enclave-key") {
        self.service = service
        self.account = account
    }

    public var hasKey: Bool { (try? loadBlob()) != nil }

    /// Creates the enclave key if this Mac doesn't have one yet. Creating needs no Touch ID; using it does.
    public func ensureKey() throws {
        if hasKey { return }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .userPresence], &error
        ) else { throw VaultError.accessControl }
        let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(compactRepresentable: false, accessControl: access)
        try storeBlob(key.dataRepresentation)
    }

    public func wrap(_ secret: Data) throws -> Data {
        let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: loadBlob())
        return try Envelope.seal(secret, to: key.publicKey)
    }

    public func unwrap(_ blob: Data, context: LAContext?) throws -> Data {
        let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: loadBlob(), authenticationContext: context)
        return try Envelope.open(blob) { try key.sharedSecretFromKeyAgreement(with: $0) }
    }

    /// Forgets this Mac's enclave key. The vault still opens with the Recovery Key.
    public func deleteKey() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private func storeBlob(_ blob: Data) throws {
        SecItemDelete(baseQuery as CFDictionary)
        var add = baseQuery
        add[kSecValueData as String] = blob
        add[kSecAttrLabel as String] = "Slinky vault key (Secure Enclave)"
        add[kSecAttrDescription as String] = "Only usable on this Mac, with Touch ID or your password."
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.keychain(status, "Saving the vault key") }
    }

    private func loadBlob() throws -> Data {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { throw VaultError.noEnclaveKey }
        guard status == errSecSuccess, let data = out as? Data else { throw VaultError.keychain(status, "Reading the vault key") }
        return data
    }
}

/// Software stand-in for tests. Never used by the app.
public final class SoftwareWrapper: KeyWrapping, @unchecked Sendable {
    private let key = P256.KeyAgreement.PrivateKey()
    public init() {}
    public func wrap(_ secret: Data) throws -> Data { try Envelope.seal(secret, to: key.publicKey) }
    public func unwrap(_ blob: Data, context: LAContext?) throws -> Data {
        try Envelope.open(blob) { try key.sharedSecretFromKeyAgreement(with: $0) }
    }
}
