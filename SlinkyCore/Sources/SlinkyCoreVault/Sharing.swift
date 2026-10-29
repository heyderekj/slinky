import CryptoKit
import Foundation
import LocalAuthentication
import SlinkyCoreShared

/// This Mac's private sharing keys. They sign what it sends and open what's sealed to its card.
public protocol SharingKeys: Sendable {
    func card(name: String) throws -> PersonCard
    /// P-256 signature, plus an ML-DSA-65 one when the card has an ML-DSA key.
    func sign(_ message: Data, context: LAContext?) throws -> (classic: Data, postQuantum: Data?)
    /// Opens an envelope sealed to this Mac's card.
    func open(_ envelope: Data, context: LAContext?) throws -> Data
}

public enum SharingError: Error, Equatable, CustomStringConvertible {
    case notForThisMac
    case badSignature
    case badFile(String)

    public var description: String {
        switch self {
        case .notForThisMac: "This wasn't shared with this Mac's card."
        case .badSignature: "This file was changed after it was made, or it isn't from who it says."
        case let .badFile(why): "This file isn't readable: \(why)"
        }
    }
}

extension PersonCard {
    /// The code two people compare to know a card is really the other person's: 4 groups of 4.
    public var fingerprint: String {
        var keys = agreement + signing
        keys.append(kem ?? Data())
        keys.append(dsa ?? Data())
        return RecoveryKey.groups(Data(SHA256.hash(data: keys).prefix(10)))
    }

    var envelopeRecipient: EnvelopeRecipient {
        get throws { EnvelopeRecipient(agreement: try P256.KeyAgreement.PublicKey(x963Representation: agreement), kem: kem) }
    }

    /// Both signatures must check out when the card has both keys, so the post-quantum one can't be stripped.
    func verify(_ message: Data, classic: Data, postQuantum: Data?) -> Bool {
        guard let key = try? P256.Signing.PublicKey(x963Representation: signing),
              let sig = try? P256.Signing.ECDSASignature(derRepresentation: classic),
              key.isValidSignature(sig, for: message) else { return false }
        guard let dsa else { return true }
        guard #available(macOS 26, *), let postQuantum, let pq = try? MLDSA65.PublicKey(rawRepresentation: dsa) else { return false }
        return pq.isValidSignature(postQuantum, for: message, context: PersonCard.signatureContext)
    }

    static let signatureContext = Data("slinky-sign-v1".utf8)

    /// A card's id comes from its signing key, so it never needs storing.
    static func id(for signing: Data) -> UUID {
        let hash = Array(SHA256.hash(data: signing))
        return UUID(uuid: (hash[0], hash[1], hash[2], hash[3], hash[4], hash[5], hash[6], hash[7],
                           hash[8], hash[9], hash[10], hash[11], hash[12], hash[13], hash[14], hash[15]))
    }
}

/// This Mac's sharing keys in the Secure Enclave: P-256 agreement and signing everywhere, ML-KEM-768 and ML-DSA-65
/// on macOS 26 and later. Opening what's sealed to this Mac needs Touch ID (or the Mac password); signing doesn't.
public final class SharingIdentity: SharingKeys, @unchecked Sendable {
    private let agreementBlob: KeychainBlob
    private let signingBlob: KeychainBlob
    private let kemBlob: KeychainBlob
    private let dsaBlob: KeychainBlob

    public init(service: String = "com.slinky.app") {
        agreementBlob = KeychainBlob(service: service, account: "sharing-agreement", label: "Slinky sharing key (Secure Enclave)")
        signingBlob = KeychainBlob(service: service, account: "sharing-signing", label: "Slinky signing key (Secure Enclave)")
        kemBlob = KeychainBlob(service: service, account: "sharing-kem", label: "Slinky sharing key, post-quantum (Secure Enclave)")
        dsaBlob = KeychainBlob(service: service, account: "sharing-dsa", label: "Slinky signing key, post-quantum (Secure Enclave)")
    }

    public var exists: Bool { agreementBlob.exists && signingBlob.exists }

    /// Makes the keys this Mac doesn't have yet. No Touch ID to make them.
    public func ensureKeys() throws {
        if !agreementBlob.exists {
            try agreementBlob.store(SecureEnclave.P256.KeyAgreement.PrivateKey(compactRepresentable: false, accessControl: KeychainBlob.presenceAccess()).dataRepresentation)
        }
        if !signingBlob.exists {
            try signingBlob.store(SecureEnclave.P256.Signing.PrivateKey(compactRepresentable: false, accessControl: KeychainBlob.silentAccess()).dataRepresentation)
        }
        if #available(macOS 26, *) {
            if !kemBlob.exists, let key = try? SecureEnclave.MLKEM768.PrivateKey(accessControl: KeychainBlob.presenceAccess()) {
                try kemBlob.store(key.dataRepresentation)
            }
            if !dsaBlob.exists, let key = try? SecureEnclave.MLDSA65.PrivateKey(accessControl: KeychainBlob.silentAccess()) {
                try dsaBlob.store(key.dataRepresentation)
            }
        }
    }

    /// Forgets this Mac's sharing keys. Things already shared with it can't be opened here any more.
    public func deleteKeys() {
        [agreementBlob, signingBlob, kemBlob, dsaBlob].forEach { $0.delete() }
    }

    public func card(name: String) throws -> PersonCard {
        try ensureKeys()
        let signing = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: signingBlob.load()).publicKey.x963Representation
        var kem: Data?, dsa: Data?
        if #available(macOS 26, *) {
            kem = try? SecureEnclave.MLKEM768.PrivateKey(dataRepresentation: kemBlob.load()).publicKey.rawRepresentation
            dsa = try? SecureEnclave.MLDSA65.PrivateKey(dataRepresentation: dsaBlob.load()).publicKey.rawRepresentation
        }
        return PersonCard(id: PersonCard.id(for: signing), name: name,
                          agreement: try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: agreementBlob.load()).publicKey.x963Representation,
                          signing: signing, kem: kem, dsa: dsa, made: .now)
    }

    /// Signing doesn't ask: the app asks first for anything a person does on purpose (sharing, changing members).
    public func sign(_ message: Data, context: LAContext?) throws -> (classic: Data, postQuantum: Data?) {
        let classic = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: signingBlob.load(), authenticationContext: context)
            .signature(for: message).derRepresentation
        guard #available(macOS 26, *), let blob = try? dsaBlob.load() else { return (classic, nil) }
        let pq = try SecureEnclave.MLDSA65.PrivateKey(dataRepresentation: blob, authenticationContext: context)
            .signature(for: message, context: PersonCard.signatureContext)
        return (classic, pq)
    }

    public func open(_ envelope: Data, context: LAContext?) throws -> Data {
        try context?.askOnce()
        let agreement = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: agreementBlob.load(), authenticationContext: context)
        guard Envelope.isHybrid(envelope) else {
            return try Envelope.open(envelope) { try agreement.sharedSecretFromKeyAgreement(with: $0) }
        }
        guard #available(macOS 26, *) else { throw SharingError.badFile("it needs macOS 26 or later") }
        let kem = try SecureEnclave.MLKEM768.PrivateKey(dataRepresentation: kemBlob.load(), authenticationContext: context)
        return try Envelope.open(envelope, recipient: EnvelopeRecipient(agreement: agreement.publicKey, kem: kem.publicKey.rawRepresentation),
                                 agreement: { try agreement.sharedSecretFromKeyAgreement(with: $0) },
                                 decapsulate: { try kem.decapsulate($0) })
    }
}

/// Software stand-in for tests. Never used by the app.
public final class SoftwareSharingKeys: SharingKeys, @unchecked Sendable {
    private let agreement = P256.KeyAgreement.PrivateKey()
    private let signing = P256.Signing.PrivateKey()
    private let kemSeed: Data?
    private let dsaSeed: Data?

    public init(postQuantum: Bool = true) {
        if postQuantum, #available(macOS 26, *) {
            kemSeed = try? MLKEM768.PrivateKey().seedRepresentation
            dsaSeed = try? MLDSA65.PrivateKey().seedRepresentation
        } else {
            kemSeed = nil
            dsaSeed = nil
        }
    }

    public func card(name: String) throws -> PersonCard {
        var kem: Data?, dsa: Data?
        if #available(macOS 26, *) {
            kem = try kemSeed.map { try MLKEM768.PrivateKey(seedRepresentation: $0, publicKey: nil).publicKey.rawRepresentation }
            dsa = try dsaSeed.map { try MLDSA65.PrivateKey(seedRepresentation: $0, publicKey: nil).publicKey.rawRepresentation }
        }
        let signingKey = signing.publicKey.x963Representation
        return PersonCard(id: PersonCard.id(for: signingKey), name: name, agreement: agreement.publicKey.x963Representation,
                          signing: signingKey, kem: kem, dsa: dsa)
    }

    public func sign(_ message: Data, context: LAContext?) throws -> (classic: Data, postQuantum: Data?) {
        let classic = try signing.signature(for: message).derRepresentation
        guard #available(macOS 26, *), let dsaSeed else { return (classic, nil) }
        let pq = try MLDSA65.PrivateKey(seedRepresentation: dsaSeed, publicKey: nil).signature(for: message, context: PersonCard.signatureContext)
        return (classic, pq)
    }

    public func open(_ envelope: Data, context: LAContext?) throws -> Data {
        guard Envelope.isHybrid(envelope) else { return try Envelope.open(envelope) { try agreement.sharedSecretFromKeyAgreement(with: $0) } }
        guard #available(macOS 26, *), let kemSeed else { throw SharingError.notForThisMac }
        let kem = try MLKEM768.PrivateKey(seedRepresentation: kemSeed, publicKey: nil)
        return try Envelope.open(envelope, recipient: EnvelopeRecipient(agreement: agreement.publicKey, kem: kem.publicKey.rawRepresentation),
                                 agreement: { try agreement.sharedSecretFromKeyAgreement(with: $0) },
                                 decapsulate: { try kem.decapsulate($0) })
    }
}

/// A content key sealed to one card.
struct SealedKey: Codable, Equatable, Sendable {
    var card: UUID
    var key: Data
}

/// Seals a content key to every card, and finds and opens the one for this Mac.
enum ContentKey {
    static func seal(_ key: SymmetricKey, to cards: [PersonCard]) throws -> [SealedKey] {
        var raw = key.withUnsafeBytes { Data($0) }
        defer { raw.resetBytes(in: 0..<raw.count) }
        return try cards.map { SealedKey(card: $0.id, key: try Envelope.seal(raw, to: $0.envelopeRecipient)) }
    }

    static func open(_ sealed: [SealedKey], for card: PersonCard, with keys: SharingKeys, context: LAContext?) throws -> SymmetricKey {
        guard let mine = sealed.first(where: { $0.card == card.id }) else { throw SharingError.notForThisMac }
        var raw = try keys.open(mine.key, context: context)
        return VaultStore.key(from: &raw)
    }
}

/// A `.slinkyshare` file: items sealed to the people they're for, signed by the Mac that sent them.
/// Nothing in the clear but the sender's public card, the date and the recipients' card ids.
public struct ShareFile: Codable, Sendable {
    public static let fileExtension = "slinkyshare"
    static let aad = Data("slinky-share-v1".utf8)

    var format = "slinky-share"
    var version = 1
    public var from: PersonCard
    public var made: Date
    var recipients: [SealedKey]
    var payload: Data
    var signature = Data()
    var postQuantumSignature: Data?

    /// Seals `items` to every card in `to` (the sender's own card is added, so they can open their copy too).
    public static func make(_ items: SharedItems, from keys: SharingKeys, name: String, to cards: [PersonCard],
                            context: LAContext?, now: Date = .now) throws -> Data {
        let sender = try keys.card(name: name)
        let contentKey = SymmetricKey(size: .bits256)
        var everyone = cards
        if !everyone.contains(where: { $0.id == sender.id }) { everyone.append(sender) }
        var json = try JSONEncoder.vault.encode(items)
        defer { json.resetBytes(in: 0..<json.count) }
        var file = ShareFile(from: sender, made: now, recipients: try ContentKey.seal(contentKey, to: everyone),
                             payload: try AES.GCM.seal(json, using: contentKey, authenticating: aad).combined!)
        let signed = try keys.sign(try file.signedBytes(), context: context)
        file.signature = signed.classic
        file.postQuantumSignature = signed.postQuantum
        return try JSONEncoder.vault.encode(file)
    }

    /// Reads the header without opening anything: who it's from and whether it's for this Mac.
    public static func peek(_ data: Data) throws -> ShareFile {
        let file: ShareFile
        do { file = try JSONDecoder.vault.decode(ShareFile.self, from: data) }
        catch { throw SharingError.badFile("not a Slinky share") }
        guard file.format == "slinky-share", file.version == 1 else { throw SharingError.badFile("unknown version \(file.version)") }
        return file
    }

    public func isFor(_ card: PersonCard) -> Bool { recipients.contains { $0.card == card.id } }
    public var recipientIDs: [UUID] { recipients.map(\.card) }

    /// Checks the signature, then opens the items with this Mac's keys.
    public func open(with keys: SharingKeys, name: String, context: LAContext?) throws -> SharedItems {
        guard from.verify(try signedBytes(), classic: signature, postQuantum: postQuantumSignature) else { throw SharingError.badSignature }
        let key = try ContentKey.open(recipients, for: try keys.card(name: name), with: keys, context: context)
        var json: Data
        do { json = try AES.GCM.open(AES.GCM.SealedBox(combined: payload), using: key, authenticating: Self.aad) }
        catch { throw SharingError.badFile("it didn't decrypt") }
        defer { json.resetBytes(in: 0..<json.count) }
        return try JSONDecoder.vault.decode(SharedItems.self, from: json)
    }

    /// Everything but the signatures, in a fixed order.
    func signedBytes() throws -> Data {
        var unsigned = self
        unsigned.signature = Data()
        unsigned.postQuantumSignature = nil
        return try JSONEncoder.vault.encode(unsigned)
    }
}
