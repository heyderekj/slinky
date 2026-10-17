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
    public var created: Date
    public var updated: Date

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

    public init(name: String, folders: [String] = [], variables: [Variable] = [], expected: [String] = [], now: Date = .now) {
        self.id = UUID()
        self.name = name
        self.folders = folders
        self.variables = variables
        self.expected = expected
        self.created = now
    }

    public var missing: [String] {
        let have = Set(variables.map(\.name))
        return expected.filter { !have.contains($0) }
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
    public var created: Date
    public var updated: Date

    public init(name: String, value: String, provider: String? = nil, isLive: Bool = false, expires: Date? = nil,
                agentPolicy: AgentPolicy? = nil, note: String? = nil, now: Date = .now) {
        self.id = UUID()
        self.name = name
        self.value = value
        self.provider = provider
        self.isLive = isLive
        self.expires = expires
        // Live keys stay human-only unless you say otherwise.
        self.agentPolicy = agentPolicy ?? (isLive ? .neverLeaves : .agentsCanUse)
        self.note = note
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
    public var created: Date

    public init(account: String, username: String? = nil, codes: [String], regenerated: Date? = .now, now: Date = .now) {
        self.id = UUID()
        self.account = account
        self.username = username
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
    public var printedCopy: Bool
    public var created: Date

    public init(label: String, kind: KeptKind = .other, from: String? = nil, value: String, note: String? = nil, now: Date = .now) {
        self.id = UUID()
        self.label = label
        self.kind = kind
        self.from = from
        self.value = value
        self.note = note
        self.printedCopy = false
        self.created = now
    }
}

public struct VaultDocument: Codable, Sendable, Equatable {
    public var formatVersion: Int = 1
    public var projects: [Project] = []
    public var keys: [Key] = []
    public var codeSets: [CodeSet] = []
    public var kept: [KeptItem] = []

    public init() {}

    public var isEmpty: Bool { projects.isEmpty && keys.isEmpty && codeSets.isEmpty && kept.isEmpty }
    public var secretCount: Int {
        projects.reduce(0) { $0 + $1.variables.filter { !$0.isPlain }.count } + keys.count + kept.count
    }
}
