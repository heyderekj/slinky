import CryptoKit
import Foundation

/// The printed Recovery Key: 160 random bits, shown once as 8 groups of 4 (Crockford base32).
/// It opens the vault on any Mac. Slinky never stores it.
public struct RecoveryKey: Sendable, Equatable {
    public let bytes: Data

    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    public static func generate() -> RecoveryKey {
        var raw = [UInt8](repeating: 0, count: 20)
        let status = SecRandomCopyBytes(kSecRandomDefault, raw.count, &raw)
        precondition(status == errSecSuccess, "No randomness available")
        return RecoveryKey(bytes: Data(raw))
    }

    public init(bytes: Data) { self.bytes = bytes }

    /// Accepts what people actually type: any case, spaces or dashes, O for 0, I or L for 1.
    public init?(_ typed: String) {
        let cleaned = typed.uppercased()
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "I", with: "1")
            .replacingOccurrences(of: "L", with: "1")
            .filter { $0 != "-" && $0 != " " && $0 != "\n" }
        guard cleaned.count == 32 else { return nil }
        var bits = 0, value = 0
        var out = Data()
        for ch in cleaned {
            guard let index = Self.alphabet.firstIndex(of: ch) else { return nil }
            value = (value << 5) | index
            bits += 5
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((value >> bits) & 0xFF))
            }
        }
        guard out.count == 20 else { return nil }
        self.bytes = out
    }

    /// "K7QX-2MPD-…" (8 groups of 4).
    public var display: String {
        var bits = 0, value = 0
        var chars: [Character] = []
        for byte in bytes {
            value = (value << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                chars.append(Self.alphabet[(value >> bits) & 31])
            }
        }
        return stride(from: 0, to: chars.count, by: 4).map { String(chars[$0..<min($0 + 4, chars.count)]) }.joined(separator: "-")
    }

    var symmetricKey: SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: bytes), salt: Data("slinky-recovery-v1".utf8),
                               info: Data("vault-key-wrap".utf8), outputByteCount: 32)
    }

    func wrap(_ secret: Data) throws -> Data { try AES.GCM.seal(secret, using: symmetricKey).combined! }

    func unwrap(_ blob: Data) throws -> Data {
        do { return try AES.GCM.open(AES.GCM.SealedBox(combined: blob), using: symmetricKey) }
        catch { throw VaultError.wrongRecoveryKey }
    }
}
