import CryptoKit
import Foundation
import LocalAuthentication
import SlinkyCoreShared

/// A `.slinkyproject` file in a folder the team syncs (shared iCloud Drive folder, Dropbox, a NAS). The project's
/// variables, sealed with a project key; the key sealed to every member's Mac. Two signatures: one by a member over
/// who's in it (only someone already in it can change that), one by whoever saved it last over everything.
/// Nothing in the clear but the project id, the members' names and public cards, and dates.
public struct SharedProjectFile: Codable, Sendable {
    public static let fileExtension = "slinkyproject"
    static let aad = Data("slinky-project-v1".utf8)

    var format = "slinky-project"
    var version = 1
    public var project: UUID
    public var members: [SharedMember]
    var keys: [SealedKey]
    public var epoch: Int
    public var membersChanged: Date
    /// The card that signed the members list.
    public var membersSignedBy: PersonCard
    var membersSignature = Data()
    var membersPostQuantumSignature: Data?
    var payload: Data
    public var saved: Date
    public var savedBy: PersonCard
    var signature = Data()
    var postQuantumSignature: Data?

    public enum Problem: Error, Equatable, CustomStringConvertible {
        /// Signed by someone who wasn't in the project.
        case notAMember
        /// The members list changed without a signature from someone who was already in it.
        case membersNotSigned
        case badSignature
        /// An older copy than this Mac already has (a rollback, or a slow sync).
        case older
        case notForThisMac

        public var description: String {
            switch self {
            case .notAMember: "This copy was saved by someone who isn't in the project."
            case .membersNotSigned: "Who's in this project was changed by someone who wasn't in it."
            case .badSignature: "This copy was changed after it was saved, or it isn't from who it says."
            case .older: "This copy is older than the one Slinky already has."
            case .notForThisMac: "This project isn't shared with this Mac."
            }
        }
    }

    // MARK: Writing

    /// A new shared project: a fresh key, sealed to every member's cards. `me` must be among the members.
    public static func start(_ project: Project, members: [SharedMember], me: PersonCard, keys: SharingKeys,
                             fileName: String, now: Date = .now) throws -> (file: Data, sharing: ProjectSharing) {
        let key = SymmetricKey(size: .bits256)
        let sharing = ProjectSharing(members: members, key: key.withUnsafeBytes { Data($0) }, epoch: 1, fileName: fileName, seen: now)
        return (try write(project, sharing: sharing, me: me, keys: keys, membersChanged: now, now: now), sharing)
    }

    /// Writes the project as it is in this vault. `membersChanged` is set when this write changes who's in it.
    public static func write(_ project: Project, sharing: ProjectSharing, me: PersonCard, keys: SharingKeys,
                             membersChanged: Date? = nil, previous: SharedProjectFile? = nil, now: Date = .now) throws -> Data {
        guard sharing.member(for: me) != nil else { throw Problem.notAMember }
        var raw = sharing.key
        defer { raw.resetBytes(in: 0..<raw.count) }
        let key = VaultStore.key(from: &raw)
        let myName = sharing.member(for: me)?.name ?? me.name
        var json = try JSONEncoder.vault.encode(payload(of: project, writer: myName))
        defer { json.resetBytes(in: 0..<json.count) }

        // Unchanged members keep the earlier members signature (and their sealed keys), so a member who didn't
        // change the list can still write.
        var file: SharedProjectFile
        if membersChanged == nil, let previous, previous.members == sharing.members, previous.epoch == sharing.epoch {
            file = previous
        } else {
            file = SharedProjectFile(project: project.id, members: sharing.members,
                                     keys: try ContentKey.seal(key, to: sharing.everyCard), epoch: sharing.epoch,
                                     membersChanged: membersChanged ?? now, membersSignedBy: me,
                                     payload: Data(), saved: now, savedBy: me)
            let signed = try keys.sign(try file.membersBytes(), context: nil)
            file.membersSignature = signed.classic
            file.membersPostQuantumSignature = signed.postQuantum
        }
        file.payload = try AES.GCM.seal(json, using: key, authenticating: aad + Data(project.id.uuidString.utf8)).combined!
        file.saved = now
        file.savedBy = me
        let signed = try keys.sign(try file.signedBytes(), context: nil)
        file.signature = signed.classic
        file.postQuantumSignature = signed.postQuantum
        return try JSONEncoder.vault.encode(file)
    }

    /// What's shared: the variables and expected names. Folders are each Mac's own; sharing is in the header.
    /// Changes made in this vault (no `updatedBy`) go out under the writer's name.
    static func payload(of project: Project, writer: String) -> Project {
        var shared = project
        shared.folders = []
        shared.sharing = nil
        for i in shared.variables.indices where shared.variables[i].updatedBy == nil { shared.variables[i].updatedBy = writer }
        return shared
    }

    // MARK: Reading

    public static func read(_ data: Data) throws -> SharedProjectFile {
        let file: SharedProjectFile
        do { file = try JSONDecoder.vault.decode(SharedProjectFile.self, from: data) }
        catch { throw SharingError.badFile("not a shared Slinky project") }
        guard file.format == "slinky-project", file.version == 1 else { throw SharingError.badFile("unknown version \(file.version)") }
        return file
    }

    /// Checks a copy against what this vault knew (`known`, nil when joining):
    /// - the members list is signed by someone in it, and when it changed, by someone who was in the known list;
    /// - the copy is signed by a current member;
    /// - it isn't older than the copy this vault last saw.
    public func check(against known: ProjectSharing?) throws {
        guard membersSignedBy.verify(try membersBytes(), classic: membersSignature, postQuantum: membersPostQuantumSignature) else {
            throw Problem.badSignature
        }
        guard savedBy.verify(try signedBytes(), classic: signature, postQuantum: postQuantumSignature) else { throw Problem.badSignature }
        guard members.contains(where: { $0.has(savedBy) }) else { throw Problem.notAMember }
        if let known {
            if members != known.members || epoch != known.epoch {
                guard known.member(for: membersSignedBy) != nil, epoch >= known.epoch else { throw Problem.membersNotSigned }
            }
            if let seen = known.seen, saved < seen { throw Problem.older }
        } else {
            guard members.contains(where: { $0.has(membersSignedBy) }) else { throw Problem.membersNotSigned }
        }
    }

    /// Opens the project key with this Mac's keys (Touch ID). Only needed when joining or when the key changed.
    public func openKey(me: PersonCard, keys: SharingKeys, context: LAContext?) throws -> Data {
        guard isFor(me) else { throw Problem.notForThisMac }
        let key = try ContentKey.open(self.keys, for: me, with: keys, context: context)
        return key.withUnsafeBytes { Data($0) }
    }

    public func isFor(_ card: PersonCard) -> Bool { keys.contains { $0.card == card.id } }

    /// The project inside, with the key this vault holds. Variables last changed by `myName` read as this vault's own.
    public func project(key raw: Data, myName: String?) throws -> Project {
        var raw = raw
        defer { raw.resetBytes(in: 0..<raw.count) }
        let key = VaultStore.key(from: &raw)
        var json: Data
        do { json = try AES.GCM.open(AES.GCM.SealedBox(combined: payload), using: key, authenticating: Self.aad + Data(project.uuidString.utf8)) }
        catch { throw SharingError.badFile("it didn't decrypt") }
        defer { json.resetBytes(in: 0..<json.count) }
        var shared = try JSONDecoder.vault.decode(Project.self, from: json)
        for i in shared.variables.indices where shared.variables[i].updatedBy == myName { shared.variables[i].updatedBy = nil }
        return shared
    }

    /// The local view of sharing after reading this copy.
    public func sharing(key: Data, fileName: String) -> ProjectSharing {
        ProjectSharing(members: members, key: key, epoch: epoch, fileName: fileName, seen: saved)
    }

    // MARK: Signed parts

    func membersBytes() throws -> Data {
        struct Part: Encodable {
            let format: String, version: Int, project: UUID, members: [SharedMember], keys: [SealedKey]
            let epoch: Int, membersChanged: Date, membersSignedBy: PersonCard
        }
        return try JSONEncoder.vault.encode(Part(format: format, version: version, project: project, members: members, keys: keys,
                                                 epoch: epoch, membersChanged: membersChanged, membersSignedBy: membersSignedBy))
    }

    func signedBytes() throws -> Data {
        var unsigned = self
        unsigned.signature = Data()
        unsigned.postQuantumSignature = nil
        return try JSONEncoder.vault.encode(unsigned)
    }
}

extension ProjectSharing {
    /// Removing someone: a new key (a new epoch) sealed only to who's left. What they already saw, they keep;
    /// the app follows this with a list of keys to replace.
    public func removing(_ member: SharedMember) -> ProjectSharing {
        var next = self
        next.members.removeAll { $0 == member }
        next.key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        next.epoch += 1
        return next
    }

    /// Adding someone, or a new Mac of someone's: same key, more cards.
    public func adding(_ member: SharedMember) -> ProjectSharing {
        var next = self
        if let i = next.members.firstIndex(where: { $0.cards.contains(where: { card in member.has(card) }) }) {
            for card in member.cards where !next.members[i].has(card) { next.members[i].cards.append(card) }
        } else {
            next.members.append(member)
        }
        return next
    }
}
