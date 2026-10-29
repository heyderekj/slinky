import CryptoKit
import Foundation
import Testing
@testable import SlinkyCoreShared
@testable import SlinkyCoreVault

@Suite("Post-quantum lock")
struct PostQuantumTests {
    func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("slinky-test-\(UUID().uuidString)/vault.slinky")
    }

    @Test func hybridEnvelopeRoundTrip() throws {
        guard #available(macOS 26, *) else { return }
        let agreement = P256.KeyAgreement.PrivateKey()
        let kem = try MLKEM768.PrivateKey()
        let recipient = EnvelopeRecipient(agreement: agreement.publicKey, kem: kem.publicKey.rawRepresentation)
        let secret = Data("EXAMPLE-vault-key-32-bytes-long!".utf8)
        let blob = try Envelope.seal(secret, to: recipient)
        #expect(Envelope.isHybrid(blob))
        #expect(blob.count == 2 + 65 + 1088 + 12 + secret.count + 16)
        let opened = try Envelope.open(blob, recipient: recipient,
                                       agreement: { try agreement.sharedSecretFromKeyAgreement(with: $0) },
                                       decapsulate: { try kem.decapsulate($0) })
        #expect(opened == secret)

        // Any flipped byte fails, in the KEM ciphertext as much as anywhere.
        for index in [1, 10, 2 + 65 + 500, blob.count - 1] {
            var bad = blob
            bad[index] ^= 0x01
            #expect(throws: (any Error).self) {
                try Envelope.open(bad, recipient: recipient,
                                  agreement: { try agreement.sharedSecretFromKeyAgreement(with: $0) },
                                  decapsulate: { try kem.decapsulate($0) })
            }
        }
        // The P-256 key alone can't open it.
        #expect(throws: (any Error).self) { try Envelope.open(blob) { try agreement.sharedSecretFromKeyAgreement(with: $0) } }
    }

    @Test func classicEnvelopeStillOpens() throws {
        let agreement = P256.KeyAgreement.PrivateKey()
        let blob = try Envelope.seal(Data("EXAMPLE".utf8), to: EnvelopeRecipient(agreement: agreement.publicKey, kem: nil))
        #expect(blob.first == 0x04)
        let opened = try Envelope.open(blob, recipient: EnvelopeRecipient(agreement: agreement.publicKey, kem: nil),
                                       agreement: { try agreement.sharedSecretFromKeyAgreement(with: $0) },
                                       decapsulate: { _ in Issue.record("no KEM for a classic envelope"); return SymmetricKey(size: .bits256) })
        #expect(opened == Data("EXAMPLE".utf8))
    }

    @Test func classicVaultMovesToTheHybridLockOnUnlock() throws {
        guard #available(macOS 26, *) else { return }
        let url = tempURL()
        let mac = SoftwareWrapper()
        let store = VaultStore(url: url, enclave: mac)
        var (session, recovery) = try store.create()
        session.document.keys.append(Key(name: "STRIPE_SECRET_KEY", value: "sk_test_EXAMPLE"))
        try store.save(session)
        #expect(!store.usesHybridLock)

        mac.addKEM()   // the Mac updates to macOS 26
        #expect(try store.unlock(context: nil).document == session.document)
        #expect(store.usesHybridLock)
        #expect(try store.unlock(context: nil).document == session.document)
        // The Recovery Key is untouched by the move.
        #expect(try store.unlock(recovery: recovery).document == session.document)
    }

    @Test func newVaultOnAModernMacIsHybridFromTheStart() throws {
        guard #available(macOS 26, *) else { return }
        let store = VaultStore(url: tempURL(), enclave: SoftwareWrapper(hybrid: true))
        let (session, _) = try store.create()
        #expect(store.usesHybridLock)
        #expect(try store.unlock(context: nil).document == session.document)
    }

    @Test func keyFromRawZeroesTheBytes() {
        var raw = Data(repeating: 0xAB, count: 32)
        let key = VaultStore.key(from: &raw)
        #expect(key.bitCount == 256)
        #expect(raw.allSatisfy { $0 == 0 })
    }
}
