import CryptoKit
import Foundation
import LocalAuthentication
import Security

public enum SpikeError: Error, CustomStringConvertible {
    case keychain(OSStatus, String)
    case noBlob
    case noVault
    case accessControl(String)

    public var description: String {
        switch self {
        case let .keychain(status, op):
            let msg = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
            return "\(op) failed: OSStatus \(status) (\(msg))"
        case .noBlob: return "No Secure Enclave key stored yet. Create one first."
        case .noVault: return "No wrapped vault key on disk yet. Wrap one first."
        case let .accessControl(msg): return "SecAccessControlCreateWithFlags failed: \(msg)"
        }
    }
}

/// The Slinky storage idea in miniature:
/// a Secure Enclave key (Touch ID or password to use) wraps a random 32-byte vault key,
/// and the Secure Enclave key's opaque blob lives in the legacy login keychain.
public final class EnclaveVault {
    public let service: String
    public let account = "enclave-key"
    public let vaultFile: URL

    public init(service: String, vaultFile: URL) {
        self.service = service
        self.vaultFile = vaultFile
    }

    public static var enclaveAvailable: Bool { SecureEnclave.isAvailable }

    // MARK: Secure Enclave key

    @discardableResult
    public func createKey(context: LAContext) throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .userPresence], &error
        ) else {
            throw SpikeError.accessControl(String(describing: error?.takeRetainedValue()))
        }
        let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(
            compactRepresentable: false, accessControl: access, authenticationContext: context
        )
        try storeBlob(key.dataRepresentation)
        return key
    }

    public func loadKey(context: LAContext) throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: try loadBlob(), authenticationContext: context)
    }

    // MARK: Wrap / unwrap (ECIES: ephemeral P-256 ECDH + HKDF-SHA256 + AES-GCM)

    private static let info = Data("slinky-spike-vault-v1".utf8)

    /// Wraps a fresh random vault key to the enclave key's public key. Needs no Touch ID.
    /// Returns a fingerprint of the vault key so the round trip can be checked without printing the key.
    public func wrapNewVaultKey(to publicKey: P256.KeyAgreement.PublicKey) throws -> String {
        let vaultKey = SymmetricKey(size: .bits256)
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: publicKey)
        let wrapKey = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: ephemeral.publicKey.x963Representation, sharedInfo: Self.info, outputByteCount: 32
        )
        let sealed = try AES.GCM.seal(vaultKey.withUnsafeBytes { Data($0) }, using: wrapKey)
        var file = Data()
        file.append(ephemeral.publicKey.x963Representation) // 65 bytes
        file.append(sealed.combined!)
        try FileManager.default.createDirectory(at: vaultFile.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try file.write(to: vaultFile, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: vaultFile.path)
        let fp = Self.fingerprint(vaultKey)
        try Data(fp.utf8).write(to: vaultFile.appendingPathExtension("fingerprint"))
        return fp
    }

    /// Unwraps the vault key. The ECDH step runs inside the Secure Enclave and is what asks for Touch ID.
    public func unwrapVaultKey(with key: SecureEnclave.P256.KeyAgreement.PrivateKey) throws -> (fingerprint: String, matches: Bool) {
        guard let file = try? Data(contentsOf: vaultFile), file.count > 65 else { throw SpikeError.noVault }
        let ephemeralPublic = try P256.KeyAgreement.PublicKey(x963Representation: file.prefix(65))
        let shared = try key.sharedSecretFromKeyAgreement(with: ephemeralPublic)
        let wrapKey = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: ephemeralPublic.x963Representation, sharedInfo: Self.info, outputByteCount: 32
        )
        let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: file.dropFirst(65)), using: wrapKey)
        let fp = Self.fingerprint(SymmetricKey(data: plain))
        let expected = (try? String(contentsOf: vaultFile.appendingPathExtension("fingerprint"), encoding: .utf8)) ?? ""
        return (fp, fp == expected)
    }

    public static func fingerprint(_ key: SymmetricKey) -> String {
        let digest = SHA256.hash(data: key.withUnsafeBytes { Data($0) })
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Legacy (file-based) login keychain

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func storeBlob(_ blob: Data) throws {
        SecItemDelete(baseQuery as CFDictionary)
        var add = baseQuery
        add[kSecValueData as String] = blob
        add[kSecAttrLabel as String] = "Slinky test: Secure Enclave key blob"
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw SpikeError.keychain(status, "SecItemAdd") }
    }

    public func loadBlob() throws -> Data {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { throw SpikeError.noBlob }
        guard status == errSecSuccess, let data = out as? Data else { throw SpikeError.keychain(status, "SecItemCopyMatching") }
        return data
    }
}

public enum SpikePaths {
    public static var supportDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SlinkySpike", isDirectory: true)
    }
    public static var socket: URL { supportDir.appendingPathComponent("agent.sock") }
    public static var appVault: URL { supportDir.appendingPathComponent("vault-app.bin") }
    public static var cliVault: URL { supportDir.appendingPathComponent("vault-cli.bin") }
}
