import Foundation
import Testing
@testable import SlinkyCoreShared
@testable import SlinkyCoreVault

// Every value in these tests is fake.

@Suite("Shared projects")
struct SharedProjectTests {
    struct Mac {
        let keys = SoftwareSharingKeys()
        let card: PersonCard
        init(_ name: String) { card = try! keys.card(name: name) }
        var member: SharedMember { SharedMember(name: card.name, cards: [card]) }
    }

    func project() -> Project {
        var p = Project(name: "harvous", folders: ["/Users/EXAMPLE/harvous"])
        p.variables = [Variable(name: "STRIPE_SECRET_KEY", values: [.local: "sk_test_EXAMPLE"])]
        return p
    }

    @Test func startJoinAndEdit() throws {
        let derek = Mac("Derek"), ana = Mac("Ana")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let (data, mine) = try SharedProjectFile.start(project(), members: [derek.member, ana.member], me: derek.card,
                                                       keys: derek.keys, fileName: "harvous.slinkyproject", now: start)
        #expect(!String(decoding: data, as: UTF8.self).contains("EXAMPLE"))

        // Ana joins: checks it with nothing known yet, opens the key with her Mac, reads the project.
        let file = try SharedProjectFile.read(data)
        try file.check(against: nil)
        let key = try file.openKey(me: ana.card, keys: ana.keys, context: nil)
        var hers = try file.project(key: key, myName: "Ana")
        #expect(hers.folders.isEmpty)   // folders stay on Derek's Mac
        #expect(hers.variables.first?.updatedBy == "Derek")
        var anaSharing = file.sharing(key: key, fileName: "harvous.slinkyproject")
        #expect(anaSharing.key == mine.key)

        // Ana changes a value and writes. Derek reads it, and sees who changed it.
        hers.variables[0].setValue("sk_test_EXAMPLE_2", in: .local)
        hers.variables[0].updatedBy = nil
        let later = start.addingTimeInterval(60)
        let edited = try SharedProjectFile.write(hers, sharing: anaSharing, me: ana.card, keys: ana.keys, previous: file, now: later)
        let derekReads = try SharedProjectFile.read(edited)
        try derekReads.check(against: mine)
        let theirs = try derekReads.project(key: mine.key, myName: "Derek")
        #expect(theirs.variables[0].value(in: .local) == "sk_test_EXAMPLE_2")
        #expect(theirs.variables[0].updatedBy == "Ana")
        let merged = VaultMerge.mergeProject(project(), theirs)
        #expect(merged.variables.contains { $0.value(in: .local) == "sk_test_EXAMPLE_2" })

        // The same copy again later is fine; an older one is refused.
        anaSharing.seen = later
        try derekReads.check(against: anaSharing)
        #expect(throws: SharedProjectFile.Problem.older) { try file.check(against: anaSharing) }
    }

    @Test func outsidersCantWriteOrChangeMembers() throws {
        let derek = Mac("Derek"), ana = Mac("Ana"), eve = Mac("Eve")
        let (data, mine) = try SharedProjectFile.start(project(), members: [derek.member, ana.member], me: derek.card,
                                                       keys: derek.keys, fileName: "p.slinkyproject")
        let file = try SharedProjectFile.read(data)

        // Eve isn't a member: she can't write with the members list as it is.
        #expect(throws: SharedProjectFile.Problem.notAMember) {
            try SharedProjectFile.write(project(), sharing: mine, me: eve.card, keys: eve.keys, previous: file)
        }
        // She adds herself and signs it all with her own keys: refused, she wasn't in the list Derek knows.
        // She doesn't have the project key, so she makes one up.
        var hers = mine.adding(eve.member)
        hers.key = Data(repeating: 7, count: 32)
        let forged = try SharedProjectFile.write(project(), sharing: hers, me: eve.card, keys: eve.keys,
                                                 membersChanged: .now, previous: file)
        #expect(throws: SharedProjectFile.Problem.membersNotSigned) { try SharedProjectFile.read(forged).check(against: mine) }
        // And the real key was never sealed to her.
        #expect(throws: SharedProjectFile.Problem.notForThisMac) { _ = try file.openKey(me: eve.card, keys: eve.keys, context: nil) }

        // A flipped byte in the payload breaks the writer's signature.
        var tampered = file
        tampered.payload[tampered.payload.count - 1] ^= 1
        #expect(throws: SharedProjectFile.Problem.badSignature) { try tampered.check(against: mine) }
    }

    @Test func removingSomeoneChangesTheKey() throws {
        let derek = Mac("Derek"), ana = Mac("Ana"), ben = Mac("Ben")
        let (data, before) = try SharedProjectFile.start(project(), members: [derek.member, ana.member, ben.member], me: derek.card,
                                                         keys: derek.keys, fileName: "p.slinkyproject")
        let first = try SharedProjectFile.read(data)
        let benKnew = first.sharing(key: try first.openKey(me: ben.card, keys: ben.keys, context: nil), fileName: "p.slinkyproject")

        let after = before.removing(ben.member)
        #expect(after.key != before.key)
        #expect(after.epoch == before.epoch + 1)
        let removed = try SharedProjectFile.read(SharedProjectFile.write(project(), sharing: after, me: derek.card, keys: derek.keys,
                                                                          membersChanged: .now, previous: first))
        // Ana accepts the change (Derek was a member) and can open the new key; Ben can't.
        let anaKnew = first.sharing(key: try first.openKey(me: ana.card, keys: ana.keys, context: nil), fileName: "p.slinkyproject")
        try removed.check(against: anaKnew)
        #expect(try removed.openKey(me: ana.card, keys: ana.keys, context: nil) == after.key)
        #expect(throws: SharedProjectFile.Problem.notForThisMac) { _ = try removed.openKey(me: ben.card, keys: ben.keys, context: nil) }

        // Ben, removed, writes the old list back: refused by anyone who has seen the removal.
        let derekNow = removed.sharing(key: after.key, fileName: "p.slinkyproject")
        let comeback = try SharedProjectFile.write(project(), sharing: benKnew, me: ben.card, keys: ben.keys,
                                                   membersChanged: .now.addingTimeInterval(5), previous: first, now: .now.addingTimeInterval(5))
        #expect(throws: SharedProjectFile.Problem.membersNotSigned) { try SharedProjectFile.read(comeback).check(against: derekNow) }
    }

    @Test func aNewMacJoinsItsPerson() throws {
        let derek = Mac("Derek"), ana = Mac("Ana"), anasLaptop = Mac("Ana")
        let (_, sharing) = try SharedProjectFile.start(project(), members: [derek.member, ana.member], me: derek.card,
                                                       keys: derek.keys, fileName: "p.slinkyproject")
        let more = sharing.adding(SharedMember(name: "Ana", cards: [ana.card, anasLaptop.card]))
        #expect(more.members.count == 2)
        #expect(more.members[1].cards.count == 2)
        #expect(more.key == sharing.key)
    }
}
