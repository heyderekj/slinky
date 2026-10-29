import Foundation
import Testing
@testable import SlinkyCoreShared
@testable import SlinkyCoreVault

// Every value in these tests is fake.

@Suite("Sharing")
struct SharingTests {
    let items = SharedItems(keys: [Key(name: "STRIPE_SECRET_KEY", value: "sk_test_EXAMPLE")],
                            variables: [Variable(name: "RESEND_API_KEY", values: [.local: "re_EXAMPLE"])],
                            projectName: "harvous")

    @Test func cardTextRoundTripAndFingerprint() throws {
        let ana = try SoftwareSharingKeys().card(name: "Ana")
        let text = ana.text
        #expect(text.hasPrefix("slinky-card:v1:"))
        #expect(!text.contains("+") && !text.contains("/") && !text.contains("="))
        // A chat app wrapped it and added a greeting: still reads.
        let pasted = "here's mine:\n" + text.enumerated().map { $0.offset % 60 == 59 ? "\($0.element)\n" : "\($0.element)" }.joined()
        let read = try #require(PersonCard(text: pasted))
        #expect(read == ana)
        #expect(read.fingerprint == ana.fingerprint)
        #expect(ana.fingerprint.count == 19)   // 4 groups of 4
        #expect(try SoftwareSharingKeys().card(name: "Ana").fingerprint != ana.fingerprint)
        #expect(PersonCard(text: "slinky-card:v1:EXAMPLE") == nil)
        // The id comes from the keys: same keys, same id, whatever the name.
        var renamed = ana
        renamed.name = "Ana P."
        #expect(renamed.sameKeys(as: ana) && renamed.fingerprint == ana.fingerprint)
    }

    @Test func shareOpensForEachRecipientAndTheSender() throws {
        let me = SoftwareSharingKeys(), ana = SoftwareSharingKeys(), ben = SoftwareSharingKeys(postQuantum: false)
        let data = try ShareFile.make(items, from: me, name: "Derek", to: [ana.card(name: "Ana"), ben.card(name: "Ben")], context: nil)
        #expect(!String(decoding: data, as: UTF8.self).contains("EXAMPLE"))
        #expect(!String(decoding: data, as: UTF8.self).contains("STRIPE"))

        let file = try ShareFile.peek(data)
        #expect(file.from.name == "Derek")
        #expect(try file.isFor(ana.card(name: "Ana")))
        #expect(try file.open(with: ana, name: "Ana", context: nil) == items)
        #expect(try file.open(with: ben, name: "Ben", context: nil) == items)   // a Mac before macOS 26
        #expect(try file.open(with: me, name: "Derek", context: nil) == items)

        let stranger = SoftwareSharingKeys()
        #expect(throws: SharingError.notForThisMac) { try file.open(with: stranger, name: "Eve", context: nil) }
    }

    @Test func tamperingIsCaught() throws {
        let me = SoftwareSharingKeys(), ana = SoftwareSharingKeys()
        let data = try ShareFile.make(items, from: me, name: "Derek", to: [ana.card(name: "Ana")], context: nil)

        // A changed payload.
        var file = try ShareFile.peek(data)
        file.payload[file.payload.count - 1] ^= 1
        #expect(throws: SharingError.badSignature) { try file.open(with: ana, name: "Ana", context: nil) }

        // A changed sender name.
        file = try ShareFile.peek(data)
        file.from.name = "Ana's manager"
        #expect(throws: SharingError.badSignature) { try file.open(with: ana, name: "Ana", context: nil) }

        // The post-quantum signature stripped from a card that has an ML-DSA key.
        file = try ShareFile.peek(data)
        if file.from.dsa != nil {
            file.postQuantumSignature = nil
            #expect(throws: SharingError.badSignature) { try file.open(with: ana, name: "Ana", context: nil) }
        }

        // Someone re-signs with their own keys but keeps the sender's card: the signature doesn't match the card.
        let eve = SoftwareSharingKeys()
        file = try ShareFile.peek(data)
        let forged = try eve.sign(try file.signedBytes(), context: nil)
        file.signature = forged.classic
        file.postQuantumSignature = forged.postQuantum
        #expect(throws: SharingError.badSignature) { try file.open(with: ana, name: "Ana", context: nil) }
    }

    @Test func knownPeopleMatchByKeys() throws {
        let ana = SoftwareSharingKeys()
        let card = try ana.card(name: "Ana")
        var doc = VaultDocument()
        doc.people = [Person(name: "Ana", cards: [card], checked: true)]
        #expect(doc.person(for: card)?.name == "Ana")
        // Same id and name, different keys: not Ana.
        var impostor = try SoftwareSharingKeys().card(name: "Ana")
        impostor.id = card.id
        #expect(doc.person(for: impostor) == nil)
    }
}
