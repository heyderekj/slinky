import Foundation

/// One Mac's sharing card: public keys only, so it's safe to paste anywhere. Each Mac makes its own in its
/// Secure Enclave; the private halves never leave it.
public struct PersonCard: Codable, Identifiable, Hashable, Sendable {
    /// Stable for the Mac's keys (derived from them), so the same card always has the same id.
    public var id: UUID
    public var name: String
    /// P-256 key agreement public key (x9.63).
    public var agreement: Data
    /// P-256 signing public key (x9.63).
    public var signing: Data
    /// ML-KEM-768 public key, on macOS 26 and later.
    public var kem: Data?
    /// ML-DSA-65 public key, on macOS 26 and later.
    public var dsa: Data?
    public var made: Date

    public init(id: UUID, name: String, agreement: Data, signing: Data, kem: Data? = nil, dsa: Data? = nil, made: Date = .now) {
        self.id = id
        self.name = name
        self.agreement = agreement
        self.signing = signing
        self.kem = kem
        self.dsa = dsa
        self.made = made
    }

    /// Same keys, whatever the name says.
    public func sameKeys(as other: PersonCard) -> Bool {
        agreement == other.agreement && signing == other.signing && kem == other.kem && dsa == other.dsa
    }

    // MARK: Text form

    public static let textPrefix = "slinky-card:v1:"

    /// `slinky-card:v1:<base64url>`, for pasting into a chat or an email. Public keys only.
    public var text: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = (try? encoder.encode(self)) ?? Data()
        return Self.textPrefix + json.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Reads the text form, ignoring spaces and line breaks a chat app might add.
    public init?(text: String) {
        let compact = text.filter { !$0.isWhitespace }
        guard let start = compact.range(of: Self.textPrefix) else { return nil }
        var body = String(compact[start.upperBound...])
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while body.count % 4 != 0 { body += "=" }
        guard let json = Data(base64Encoded: body), let card = try? JSONDecoder().decode(PersonCard.self, from: json),
              card.agreement.count == 65, card.signing.count == 65 else { return nil }
        self = card
    }
}

/// Someone you share with (or you: `isMe`), with a card for each of their Macs.
public struct Person: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var cards: [PersonCard]
    /// The person compared the code on the other Mac (in person or on a call).
    public var checked: Bool
    public var isMe: Bool
    public var added: Date
    /// For sync. nil means never changed since it was added.
    public var modified: Date?

    public init(name: String, cards: [PersonCard], checked: Bool = false, isMe: Bool = false, now: Date = .now) {
        self.id = UUID()
        self.name = name
        self.cards = cards
        self.checked = checked
        self.isMe = isMe
        self.added = now
    }

    public func has(_ card: PersonCard) -> Bool { cards.contains { $0.id == card.id && $0.sameKeys(as: card) } }
}

/// What goes inside a share: copies of items, values included. Lives only inside an encrypted file.
public struct SharedItems: Codable, Equatable, Sendable {
    public var keys: [Key] = []
    public var kept: [KeptItem] = []
    public var codeSets: [CodeSet] = []
    public var files: [SecretFile] = []
    /// Project variables, with the project's name so the other end can suggest one.
    public var variables: [Variable] = []
    public var projectName: String?

    public init(keys: [Key] = [], kept: [KeptItem] = [], codeSets: [CodeSet] = [], files: [SecretFile] = [],
                variables: [Variable] = [], projectName: String? = nil) {
        self.keys = keys
        self.kept = kept
        self.codeSets = codeSets
        self.files = files
        self.variables = variables
        self.projectName = projectName
    }

    public var isEmpty: Bool { keys.isEmpty && kept.isEmpty && codeSets.isEmpty && files.isEmpty && variables.isEmpty }
    public var count: Int { keys.count + kept.count + codeSets.count + files.count + variables.count }

    /// Names only, for previews and Activity.
    public var names: [String] {
        keys.map(\.name) + kept.map(\.label) + codeSets.map(\.account) + files.map(\.name) + variables.map(\.name)
    }
}

extension VaultDocument {
    public var people: [Person] {
        get { contacts ?? [] }
        set { contacts = newValue.isEmpty ? nil : newValue }
    }

    public var me: Person? { people.first { $0.isMe } }

    /// Whose card this is, if it's someone you know.
    public func person(for card: PersonCard) -> Person? { people.first { $0.has(card) } }
}

/// One person in a shared project, with every Mac (card) of theirs that can open it.
public struct SharedMember: Codable, Hashable, Sendable {
    public var name: String
    public var cards: [PersonCard]

    public init(name: String, cards: [PersonCard]) {
        self.name = name
        self.cards = cards
    }

    public func has(_ card: PersonCard) -> Bool { cards.contains { $0.id == card.id && $0.sameKeys(as: card) } }
}

/// What this vault knows about a shared project: who's in it (as last checked) and its key. Inside the vault,
/// so it's as safe as the values. Folders stay per Mac (in Settings), never here.
public struct ProjectSharing: Codable, Hashable, Sendable {
    public var members: [SharedMember]
    /// The project key, raw. Changes when someone is removed.
    public var key: Data
    /// Goes up by one each time the key changes.
    public var epoch: Int
    /// The shared file's name in the team folder.
    public var fileName: String
    /// The newest shared copy this vault has read or written, so an older one is never taken over it.
    public var seen: Date?

    public init(members: [SharedMember], key: Data, epoch: Int = 1, fileName: String, seen: Date? = nil) {
        self.members = members
        self.key = key
        self.epoch = epoch
        self.fileName = fileName
        self.seen = seen
    }

    public var everyCard: [PersonCard] { members.flatMap(\.cards) }
    public func member(for card: PersonCard) -> SharedMember? { members.first { $0.has(card) } }
}
