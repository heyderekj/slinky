import Foundation

// Everything in the vault. This whole document is encrypted at rest (see SlinkyCoreVault).

/// Where a project variable applies. Mirrors how people name their .env files.
public enum AppEnvironment: String, Codable, CaseIterable, Sendable, Identifiable {
    case local, preview, production
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .local: "Local"
        case .preview: "Preview"
        case .production: "Production"
        }
    }
}

/// How agents may use a secret. Shown as one three-way control in the inspector.
public enum AgentPolicy: String, Codable, CaseIterable, Sendable {
    case agentsCanUse, askEveryTime, neverLeaves
    public var title: String {
        switch self {
        case .agentsCanUse: "Agents can use"
        case .askEveryTime: "Ask every time"
        case .neverLeaves: "Never leaves"
        }
    }
}

/// Which picture an item shows. `nil` (or `.automatic`) lets Slinky choose: an installed app, a built-in
/// service logo, a website icon if that's turned on, then initials.
public enum IconChoice: Codable, Hashable, Sendable {
    case automatic
    /// An installed Mac app's icon, by bundle identifier.
    case app(String)
    /// A built-in service logo, by catalog id (see `ServiceCatalog`).
    case service(String)
    /// The icon saved from a website, by domain.
    case website(String)
    /// Just the initials.
    case monogram
}

/// One line of a project's .env, with a value per environment.
public struct Variable: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// Keyed by `AppEnvironment.rawValue`. A missing key means "not set in that environment".
    public var values: [String: String]
    public var isPlain: Bool
    public var provider: String?
    public var agentPolicy: AgentPolicy
    public var note: String?
    /// A web address that goes with it, like the dashboard where the key was made. Optional (added in 1.1).
    public var link: String?
    public var icon: IconChoice?
    /// Where it lives: the catalog id of the service the person manages it at (say "cloudflare"). Chosen by the
    /// person, so it beats any guess. nil means Slinky works it out from the name and link.
    public var service: String?
    public var created: Date
    public var updated: Date
    /// Who made the last change, in a shared project: the name on their card. nil for your own changes.
    public var updatedBy: String?

    public init(name: String, values: [AppEnvironment: String], isPlain: Bool = false, provider: String? = nil,
                agentPolicy: AgentPolicy = .agentsCanUse, note: String? = nil, now: Date = .now) {
        self.id = UUID()
        self.name = name
        self.values = Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })
        self.isPlain = isPlain
        self.provider = provider
        self.agentPolicy = agentPolicy
        self.note = note
        self.created = now
        self.updated = now
    }

    public func value(in env: AppEnvironment) -> String? { values[env.rawValue] }
    public mutating func setValue(_ value: String?, in env: AppEnvironment) {
        values[env.rawValue] = value
        updated = .now
    }
}

public struct Project: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// Folders linked to this project (absolute paths). Used later by `slinky run` to find the project.
    public var folders: [String]
    public var variables: [Variable]
    /// Names listed in the project's .env.example that Slinky doesn't hold yet are "missing".
    public var expected: [String]
    public var created: Date
    /// When the project itself (name, folders, expected names) last changed, for sync. nil means never since 1.5.
    public var modified: Date?
    /// Set when the project is shared with other people through a team folder (1.6).
    public var sharing: ProjectSharing?

    public init(name: String, folders: [String] = [], variables: [Variable] = [], expected: [String] = [], now: Date = .now) {
        self.id = UUID()
        self.name = name
        self.folders = folders
        self.variables = variables
        self.expected = expected
        self.created = now
    }

    /// Each name once, even if .env.example lists it twice.
    public var missing: [String] {
        var seen = Set(variables.map(\.name))
        return expected.filter { seen.insert($0).inserted }
    }
}

/// A standalone API key or personal token that isn't tied to one project.
public struct Key: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var value: String
    public var provider: String?
    public var isLive: Bool
    public var expires: Date?
    public var agentPolicy: AgentPolicy
    public var note: String?
    public var link: String?
    public var icon: IconChoice?
    /// Where it lives: the catalog id of the service the person manages it at (say "cloudflare"). Chosen by the
    /// person, so it beats any guess. nil means Slinky works it out from the name and link.
    public var service: String?
    public var created: Date
    public var updated: Date

    public init(name: String, value: String, provider: String? = nil, isLive: Bool = false, expires: Date? = nil,
                agentPolicy: AgentPolicy? = nil, note: String? = nil, link: String? = nil, now: Date = .now) {
        self.id = UUID()
        self.name = name
        self.value = value
        self.provider = provider
        self.isLive = isLive
        self.expires = expires
        // Live keys stay human-only unless you say otherwise.
        self.agentPolicy = agentPolicy ?? (isLive ? .neverLeaves : .agentsCanUse)
        self.note = note
        self.link = link
        self.created = now
        self.updated = now
    }
}

/// A set of 2FA recovery codes for one account. Codes get crossed off as they're used.
public struct CodeSet: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var account: String
    public var username: String?
    public var codes: [String]
    public var used: Set<Int>
    public var regenerated: Date?
    public var note: String?
    public var link: String?
    public var icon: IconChoice?
    /// Where it lives: the catalog id of the service the person manages it at (say "cloudflare"). Chosen by the
    /// person, so it beats any guess. nil means Slinky works it out from the name and link.
    public var service: String?
    public var created: Date
    /// When it last changed, for sync (added in 1.5).
    public var modified: Date?

    public init(account: String, username: String? = nil, codes: [String], regenerated: Date? = .now,
                note: String? = nil, link: String? = nil, now: Date = .now) {
        self.id = UUID()
        self.account = account
        self.username = username
        self.note = note
        self.link = link
        self.codes = codes
        self.used = []
        self.regenerated = regenerated
        self.created = now
    }

    public var remaining: Int { codes.count - used.count }
    public var isLow: Bool { remaining <= 3 }
    public var nextUnused: Int? { codes.indices.first { !used.contains($0) } }
}

public enum KeptKind: String, Codable, CaseIterable, Sendable {
    case recoveryKey, setupKey, licenseKey, password, other
    public var title: String {
        switch self {
        case .recoveryKey: "Recovery key"
        case .setupKey: "2FA setup key"
        case .licenseKey: "License key"
        case .password: "Password"
        case .other: "Recovery key"
        }
    }
}

/// A recovery key or 2FA setup key: one value that gets you back into an account.
public struct KeptItem: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var label: String
    public var kind: KeptKind
    public var from: String?
    public var value: String
    public var note: String?
    public var link: String?
    public var icon: IconChoice?
    /// Where it lives: the catalog id of the service the person manages it at (say "cloudflare"). Chosen by the
    /// person, so it beats any guess. nil means Slinky works it out from the name and link.
    public var service: String?
    public var printedCopy: Bool
    public var created: Date
    /// When it last changed, for sync (added in 1.5).
    public var modified: Date?

    public init(label: String, kind: KeptKind = .other, from: String? = nil, value: String, note: String? = nil,
                link: String? = nil, now: Date = .now) {
        self.id = UUID()
        self.label = label
        self.kind = kind
        self.from = from
        self.value = value
        self.note = note
        self.link = link
        self.printedCopy = false
        self.created = now
    }
}

/// Something that was removed, kept for 30 days so it can be restored.
public enum TrashedItem: Codable, Hashable, Sendable {
    case key(Key)
    case codes(CodeSet)
    case kept(KeptItem)
    /// A variable, with the project it came from (by id, and its name for display if that project is gone).
    case variable(Variable, projectID: UUID, projectName: String)
    case project(Project)
    /// Added in 1.4.
    case file(SecretFile)

    /// The id of what was removed.
    public var itemID: UUID {
        switch self {
        case .key(let k): k.id
        case .codes(let c): c.id
        case .kept(let k): k.id
        case .variable(let v, _, _): v.id
        case .project(let p): p.id
        case .file(let f): f.id
        }
    }

    public var title: String {
        switch self {
        case .key(let k): k.name
        case .codes(let c): "\(c.account) recovery codes"
        case .kept(let k): k.label
        case .variable(let v, _, let p): "\(v.name) (\(p))"
        case .project(let p): p.name
        case .file(let f): f.name
        }
    }
}

public struct TrashEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var item: TrashedItem
    public var deletedAt: Date

    public init(_ item: TrashedItem, deletedAt: Date = .now) {
        self.id = UUID()
        self.item = item
        self.deletedAt = deletedAt
    }
}

public struct VaultDocument: Codable, Sendable, Equatable {
    public var formatVersion: Int = 2
    public var projects: [Project] = []
    public var keys: [Key] = []
    public var codeSets: [CodeSet] = []
    public var kept: [KeptItem] = []
    // Added in 1.1. Optional so vaults written by 1.0 open unchanged (a missing key decodes as nil).
    /// Recently Deleted.
    public var trash: [TrashEntry]?
    /// Website icons the person chose to load: 64 px PNGs by domain. Inside the vault, so the list of
    /// services someone uses is never on disk in the clear.
    public var siteIcons: [String: Data]?
    // Added in 1.2.
    /// What was copied or used, when and by whom. Names only, never values. Newest first, capped.
    public var activity: [ActivityEntry]?
    // Added in 1.4.
    /// Small secret files: App Store Connect .p8 keys, certificates, service-account JSON.
    public var files: [SecretFile]?
    // Added in 1.5.
    /// Ids of things deleted for good, and when, so syncing never brings them back. Ids only, nothing else.
    public var removed: [UUID: Date]?
    // Added in 1.6.
    /// People you share with, and your own Macs' sharing cards. Public keys only.
    public var contacts: [Person]?

    public init() {}

    public var log: [ActivityEntry] {
        get { activity ?? [] }
        set { activity = newValue.isEmpty ? nil : Array(newValue.prefix(ActivityEntry.limit)) }
    }

    public var secretFiles: [SecretFile] {
        get { files ?? [] }
        set { files = newValue.isEmpty ? nil : newValue }
    }

    /// How long removed items wait in Recently Deleted.
    public static let trashDays = 30

    public var trashed: [TrashEntry] {
        get { trash ?? [] }
        set { trash = newValue.isEmpty ? nil : newValue }
    }

    /// Drops Recently Deleted entries older than 30 days. Returns how many went.
    @discardableResult
    public mutating func purgeTrash(now: Date = .now) -> Int {
        let cutoff = now.addingTimeInterval(-Double(Self.trashDays) * 86_400)
        let before = trashed.count
        trashed = trashed.filter { $0.deletedAt > cutoff }
        return before - trashed.count
    }

    public var isEmpty: Bool { projects.isEmpty && keys.isEmpty && codeSets.isEmpty && kept.isEmpty && secretFiles.isEmpty }
    public var secretCount: Int {
        projects.reduce(0) { $0 + $1.variables.filter { !$0.isPlain }.count } + keys.count + kept.count
    }
}
