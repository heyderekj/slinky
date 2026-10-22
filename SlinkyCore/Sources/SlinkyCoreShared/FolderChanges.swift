import Foundation

/// One name in one environment: what Slinky has now, and what the folder's files offer for it.
/// Lives in memory only, while the review is open.
public struct EnvChange: Identifiable, Sendable, Equatable {
    public enum Status: Sendable, Equatable { case new, changed, same, onlyInSlinky }

    /// A value a file offers, by the file's path inside the folder ("apps/web/.env.local").
    public struct Offer: Sendable, Equatable {
        public let source: String
        public let value: String
    }

    public var id: String { "\(environment.rawValue)|\(name)" }
    public let name: String
    public let environment: AppEnvironment
    /// Slinky's value in this environment now.
    public let current: String?
    /// Best first: the more specific file wins (`.env.local` over `.env`), then the first group listed.
    public let offers: [Offer]
    /// The name already exists in the project, in some environment.
    public let variableExists: Bool

    /// Two files offer different values.
    public var isConflict: Bool { Set(offers.map(\.value)).count > 1 }

    public func offer(picking source: String? = nil) -> Offer? {
        if let source, let picked = offers.first(where: { $0.source == source }) { return picked }
        return offers.first
    }

    public func status(picking source: String? = nil) -> Status {
        guard let offer = offer(picking: source) else { return .onlyInSlinky }
        guard let current else { return .new }
        return current == offer.value ? .same : .changed
    }
}

/// What reading a folder (or one .env file) would change in a project, environment by environment: new names,
/// changed values, the same values, and names only Slinky has. Applying never removes anything.
public struct FolderChanges: Sendable, Equatable {
    /// One file's lines, mapped to an environment.
    public struct Source: Sendable, Equatable, Identifiable {
        public let id: String
        public let environment: AppEnvironment
        public let lines: [DotEnvLine]
        public let precedence: Int

        public init(id: String, environment: AppEnvironment, lines: [DotEnvLine], precedence: Int) {
            self.id = id
            self.environment = environment
            self.lines = lines
            self.precedence = precedence
        }

        public init(_ file: ProjectScan.EnvFile, environment: AppEnvironment? = nil) {
            self.init(id: file.id, environment: environment ?? file.environment, lines: file.lines,
                      precedence: ProjectScan.precedence(of: file.fileName))
        }
    }

    /// The rows to apply, and which file's value for rows where files disagree.
    public struct Picks: Sendable, Equatable {
        public var rows: Set<EnvChange.ID>
        public var sources: [EnvChange.ID: String]
        public init(rows: Set<EnvChange.ID> = [], sources: [EnvChange.ID: String] = [:]) {
            self.rows = rows
            self.sources = sources
        }
    }

    /// Counted by name: a name is new, updated, unchanged or skipped once, however many environments it's in.
    public struct Summary: Sendable, Equatable {
        public var new = 0, updated = 0, unchanged = 0, skipped = 0
        public init(new: Int = 0, updated: Int = 0, unchanged: Int = 0, skipped: Int = 0) {
            self.new = new; self.updated = updated; self.unchanged = unchanged; self.skipped = skipped
        }
        public var changedAny: Bool { new + updated > 0 }
        /// "12 new, 3 updated, 5 unchanged, 2 skipped", leaving out the zeros.
        public var text: String {
            let parts = [(new, "new"), (updated, "updated"), (unchanged, "unchanged"), (skipped, "skipped")]
                .filter { $0.0 > 0 }.map { "\($0.0.formatted()) \($0.1)" }
            return parts.isEmpty ? "Nothing to change" : parts.joined(separator: ", ")
        }
    }

    /// Local, Preview, Production; within each, names in the order the files list them.
    public let changes: [EnvChange]
    /// Every name the folder's example files list.
    public let expected: [String]
    public let expectedAdded: [String]
    public let expectedRemoved: [String]

    public static func compare(_ project: Project, with sources: [Source], expected: [String] = []) -> FolderChanges {
        // Groups rank by first appearance; within a group the more specific file wins.
        var groupRank: [String: Int] = [:]
        for s in sources where groupRank[ProjectScan.folderOf(s.id)] == nil { groupRank[ProjectScan.folderOf(s.id)] = groupRank.count }
        func rank(_ s: Source) -> (Int, Int) { (groupRank[ProjectScan.folderOf(s.id)] ?? 0, -s.precedence) }

        var changes: [EnvChange] = []
        for env in [AppEnvironment.local, .preview, .production] {
            let here = sources.filter { $0.environment == env }.sorted { rank($0) < rank($1) }
            guard !here.isEmpty else { continue }   // an environment no file touches isn't compared at all
            var order: [String] = []
            var offers: [String: [EnvChange.Offer]] = [:]
            // Files in reading order (least specific first), so names come out in the order people wrote them.
            for source in here.reversed() {
                var lastValue: [String: String] = [:]
                for line in source.lines { lastValue[line.name] = line.value }   // a name twice in one file: the last wins
                for line in source.lines where lastValue[line.name] != nil {
                    if offers[line.name] == nil { order.append(line.name) }
                    offers[line.name, default: []].insert(EnvChange.Offer(source: source.id, value: lastValue[line.name]!), at: 0)
                    lastValue[line.name] = nil
                }
            }
            for name in order {
                let variable = project.variables.first { $0.name == name }
                changes.append(EnvChange(name: name, environment: env, current: variable?.value(in: env),
                                         offers: offers[name] ?? [], variableExists: variable != nil))
            }
            for variable in project.variables where offers[variable.name] == nil {
                guard let value = variable.value(in: env) else { continue }
                changes.append(EnvChange(name: variable.name, environment: env, current: value, offers: [], variableExists: true))
            }
        }
        let have = Set(project.expected), want = Set(expected)
        return FolderChanges(changes: changes, expected: expected,
                             expectedAdded: expected.filter { !have.contains($0) },
                             expectedRemoved: project.expected.filter { !want.contains($0) })
    }

    /// New and changed rows, except a change to an empty value (more often a blank in the file than a real reset).
    public var defaultPicks: Picks {
        Picks(rows: Set(changes.filter { c in
            switch c.status() {
            case .new: true
            case .changed: !(c.offer()?.value.isEmpty ?? true)
            default: false
            }
        }.map(\.id)))
    }

    public func status(of change: EnvChange, _ picks: Picks) -> EnvChange.Status {
        change.status(picking: picks.sources[change.id])
    }

    public func summary(for picks: Picks) -> Summary {
        var summary = Summary()
        var byName: [String: [EnvChange]] = [:]
        var names: [String] = []
        for c in changes where c.status() != .onlyInSlinky {
            if byName[c.name] == nil { names.append(c.name) }
            byName[c.name, default: []].append(c)
        }
        for name in names {
            let rows = byName[name]!
            let moving = rows.filter { [.new, .changed].contains(status(of: $0, picks)) }
            if moving.contains(where: { picks.rows.contains($0.id) }) {
                if rows[0].variableExists { summary.updated += 1 } else { summary.new += 1 }
            } else if moving.isEmpty {
                summary.unchanged += 1
            } else {
                summary.skipped += 1
            }
        }
        return summary
    }

    /// Writes the picked rows into `project`. Never removes a variable or a value. New names are secret unless
    /// they're public config (`NEXT_PUBLIC_…`), with the provider Slinky recognizes. With `replaceExpected`, the
    /// project expects exactly what the example files list (when they list anything); otherwise names are added.
    @discardableResult
    public func apply(_ picks: Picks, to project: inout Project, replaceExpected: Bool = false, now: Date = .now) -> Summary {
        let summary = summary(for: picks)
        for c in changes where picks.rows.contains(c.id) {
            guard [.new, .changed].contains(status(of: c, picks)), let offer = c.offer(picking: picks.sources[c.id]) else { continue }
            if let i = project.variables.firstIndex(where: { $0.name == c.name }) {
                project.variables[i].setValue(offer.value, in: c.environment)
                project.variables[i].updated = now
            } else {
                project.variables.append(Variable(name: c.name, values: [c.environment: offer.value],
                                                  isPlain: DotEnv.isPlainName(c.name),
                                                  provider: Detector.detect(offer.value)?.provider, now: now))
            }
        }
        if replaceExpected, !expected.isEmpty {
            project.expected = expected
        } else {
            var seen = Set(project.expected)
            project.expected += expected.filter { seen.insert($0).inserted }
        }
        return summary
    }
}
