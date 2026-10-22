import SlinkyCoreShared
import SwiftUI

/// Something in the vault that needs a person to act: running out of codes, a project missing variables,
/// a key about to expire. Only shown in the sidebar when there's at least one.
struct AttentionItem: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let detail: String
    let target: SidebarItem
    /// Set for a recovery key with no copy outside Slinky: the row offers Print… and "I Have a Copy".
    var recoveryKeyID: UUID?
}

extension AppModel {
    var attention: [AttentionItem] {
        var items: [AttentionItem] = []
        for set in document.codeSets where set.isLow {
            items.append(AttentionItem(
                id: "codes-\(set.id)", symbol: "number.square",
                title: set.remaining == 0 ? "No \(set.account) codes left" : "Only \(set.remaining) \(set.account) \(set.remaining == 1 ? "code" : "codes") left",
                detail: "Make new recovery codes on \(set.account), then add them here.",
                target: .library(.recovery)))
        }
        for project in document.projects where !project.missing.isEmpty {
            let n = project.missing.count
            items.append(AttentionItem(
                id: "missing-\(project.id)", symbol: "folder",
                title: "\(project.name) is missing \(n) \(n == 1 ? "variable" : "variables")",
                detail: project.missing.prefix(4).joined(separator: ", ") + (n > 4 ? " and \(n - 4) more" : ""),
                target: .project(project.id)))
        }
        for item in document.kept where item.kind == .recoveryKey && !item.printedCopy {
            items.append(AttentionItem(
                id: "copy-\(item.id)", symbol: "printer",
                title: "\(item.label) has no copy outside Slinky",
                detail: "If you lose this Mac and your Recovery Key, a printed copy is your way back in.",
                target: .library(.recovery), recoveryKeyID: item.id))
        }
        let soon = Date.now.addingTimeInterval(14 * 86_400)
        for key in document.keys {
            guard let expires = key.expires, expires < soon else { continue }
            let days = Calendar.current.dateComponents([.day], from: .now, to: expires).day ?? 0
            items.append(AttentionItem(
                id: "expires-\(key.id)", symbol: "key",
                title: expires < .now ? "\(key.name) has expired" : days < 1 ? "\(key.name) expires today"
                    : "\(key.name) expires in \(days) \(days == 1 ? "day" : "days")",
                detail: "Make a new one\(key.provider.map { " on \($0)" } ?? ""), then replace it here.",
                target: .library(.keys)))
        }
        return items
    }
}

/// Health: one look at how your secrets are doing. A summary with a ring of every check, a tile per check that
/// says what it looked at and what it found, then the findings themselves, each with a reason and a fix.
struct AttentionView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmHistory: LeakFinding?
    @State private var confirmMove: LeakFinding?

    var body: some View {
        let checks = HealthCheck.all(model)
        let items = model.attention
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HealthSummary(checks: checks)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 196), spacing: 10)], spacing: 10) {
                        ForEach(checks) { check in
                            HealthTile(check: check) {
                                withAnimation(.snappy) { proxy.scrollTo(check.section, anchor: .top) }
                            }
                        }
                    }
                    if !model.leaks.isEmpty {
                        group("Found outside Slinky", id: HealthCheck.Section.leaks,
                              footer: "Only the names are shown. Slinky looked for exact copies of what you've saved.") {
                            ForEach(model.leaks) { finding in leakRow(finding) }
                        }
                    }
                    if !items.isEmpty {
                        group("Needs you", id: HealthCheck.Section.needs) {
                            ForEach(items) { item in AttentionRow(item: item) { model.selection = item.target } }
                        }
                    }
                    tidySection
                    Label("Every check runs on this Mac, using what's saved in Slinky. Nothing is sent anywhere.", systemImage: "lock")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
        }
        .screenTitle("Health", subtitle: model.healthCount == 0 ? "All good" : "\(model.healthCount) to look at")
        // Findings are kept in memory only, so opening Health looks again if it hasn't since unlocking.
        .task { if model.leaksChecked == nil { await model.checkForLeaks() } }
        .confirmationDialog("Remove those lines from your history?", isPresented: Binding(get: { confirmHistory != nil }, set: { if !$0 { confirmHistory = nil } })) {
            Button("Remove Lines", role: .destructive) { if let f = confirmHistory { model.cleanHistory(f) }; confirmHistory = nil }
        } message: {
            Text("Every line containing \(confirmHistory?.names.joined(separator: ", ") ?? "it") goes. The rest of your history stays.")
        }
        .confirmationDialog("Move this .env into Slinky?", isPresented: Binding(get: { confirmMove != nil }, set: { if !$0 { confirmMove = nil } })) {
            Button("Move into Slinky") { if let f = confirmMove { model.moveIntoSlinky(f) }; confirmMove = nil }
        } message: {
            Text("Its variables are saved to the project, a .env.example with names only is written if there isn't one, and the file goes to the Trash. Use slinky run to start your app with them.")
        }
    }

    private func leakRow(_ finding: LeakFinding) -> some View {
        HealthRow(symbol: symbol(finding), tint: .orange, title: finding.title, detail: finding.detail, path: finding.shownPath) {
            switch finding.place {
            case .envFile:
                Button("Move into Slinky") { confirmMove = finding }.glassProminentButton()
            case .history:
                Button("Remove Lines…") { confirmHistory = finding }.glassProminentButton()
            default:
                Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: finding.path)]) }
            }
        }
    }

    private func symbol(_ f: LeakFinding) -> String {
        switch f.place {
        case .envFile, .projectFile: "doc.text"
        case .commit: "arrow.triangle.branch"
        case .transcript: "bubble.left.and.text.bubble.right"
        case .history: "terminal"
        }
    }

    @ViewBuilder
    private var tidySection: some View {
        let unused = model.unusedKeys
        let dupes = model.duplicates
        if !unused.isEmpty || !dupes.isEmpty {
            group("Tidy up", id: HealthCheck.Section.tidy) {
                if !unused.isEmpty {
                    HealthRow(symbol: "clock", tint: .secondary,
                              title: "Not used in over 60 days: \(unused.prefix(3).map(\.name).joined(separator: ", "))\(unused.count > 3 ? " and \(unused.count - 3) more" : "")",
                              detail: "If you don't need them any more, delete them here and revoke them on the service.") {
                        Button("Show") { model.selection = .library(.keys) }
                    }
                }
                ForEach(dupes, id: \.self) { names in
                    HealthRow(symbol: "square.on.square", tint: .secondary,
                              title: (names.count == 2 ? "Saved twice: " : "Saved \(names.count) times: ") + names.formatted(.list(type: .and)),
                              detail: "Same value in \(names.count == 2 ? "two" : "\(names.count)") places. Keeping one makes replacing it later simpler.") {
                        Button("Show") { model.selection = .library(.all) }
                    }
                }
            }
        }
    }

    private func group<Content: View>(_ title: String, id: HealthCheck.Section, footer: String? = nil,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.semibold))
            VStack(spacing: 8) { content() }
            if let footer { Text(footer).font(.caption).foregroundStyle(.secondary) }
        }
        .id(id)
    }
}

/// One thing Health looks at, and how it went.
struct HealthCheck: Identifiable {
    enum Section: Hashable { case leaks, needs, tidy }
    enum Status: Equatable { case clear, found(Int), notChecked, checking, nothingToCheck }

    let id: String
    let symbol: String
    let title: String
    /// What it looked at, in a few words.
    let scope: String
    let status: Status
    let section: Section

    var tint: Color {
        switch status {
        case .clear: .green
        case .found: .orange
        case .notChecked, .checking, .nothingToCheck: .secondary
        }
    }

    @MainActor
    static func all(_ model: AppModel) -> [HealthCheck] {
        let leaks = model.leaks
        let leakStatus: (Int) -> Status = { n in
            if model.checkingLeaks { return .checking }
            if model.leaksChecked == nil { return .notChecked }
            return n == 0 ? .clear : .found(n)
        }
        let inFiles = leaks.filter { if case .transcript = $0.place { false } else if case .history = $0.place { false } else { true } }.count
        let inChats = leaks.filter { if case .transcript = $0.place { true } else { false } }.count
        let inHistory = leaks.filter { if case .history = $0.place { true } else { false } }.count
        let needs = model.attention
        let count: (String) -> Int = { prefix in needs.filter { $0.id.hasPrefix(prefix) }.count }
        let found: (Int) -> Status = { $0 == 0 ? .clear : .found($0) }
        let projects = model.document.projects.count
        let tidy = model.unusedKeys.count + model.duplicates.count
        return [
            HealthCheck(id: "files", symbol: "folder", title: "Project files",
                        scope: projects == 0 ? "Link a project folder to check it" : "\(projects) linked \(projects == 1 ? "project" : "projects") and their git history",
                        status: projects == 0 ? .nothingToCheck : leakStatus(inFiles), section: .leaks),
            HealthCheck(id: "chats", symbol: "bubble.left.and.text.bubble.right", title: "AI conversations",
                        scope: "Claude Code, Codex and Cursor", status: leakStatus(inChats), section: .leaks),
            HealthCheck(id: "shell", symbol: "terminal", title: "Shell history",
                        scope: "zsh, bash and fish", status: leakStatus(inHistory), section: .leaks),
            HealthCheck(id: "expiring", symbol: "calendar.badge.clock", title: "Expiring keys",
                        scope: "Within the next 14 days", status: found(count("expires-")), section: .needs),
            HealthCheck(id: "codes", symbol: "number.square", title: "Recovery codes",
                        scope: "3 or fewer left", status: found(count("codes-")), section: .needs),
            HealthCheck(id: "copies", symbol: "printer", title: "Copies outside Slinky",
                        scope: "Recovery keys on paper or elsewhere", status: found(count("copy-")), section: .needs),
            HealthCheck(id: "missing", symbol: "list.bullet.rectangle", title: "Project variables",
                        scope: "Names in .env.example", status: found(count("missing-")), section: .needs),
            HealthCheck(id: "tidy", symbol: "sparkles", title: "Tidy up",
                        scope: "Unused for 60 days, or saved twice", status: found(tidy), section: .tidy),
        ]
    }
}

/// The top of Health: a ring with one segment per check, what it all adds up to, and Check Now.
private struct HealthSummary: View {
    @Environment(AppModel.self) private var model
    let checks: [HealthCheck]

    var body: some View {
        // Tidy-ups are suggestions, not problems: left out here and from the sidebar badge (healthCount), so they agree.
        let issues = checks.filter { $0.section != .tidy }.reduce(0) { n, c in if case let .found(k) = c.status { n + k } else { n } }
        let unchecked = checks.contains { $0.status == .notChecked }
        HStack(spacing: 22) {
            HealthRing(checks: checks, spinning: model.checkingLeaks)
                .frame(width: 96, height: 96)
                .overlay {
                    if model.checkingLeaks {
                        ProgressView().controlSize(.small)
                    } else if issues > 0 {
                        Text("\(issues)").font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(.orange)
                            .contentTransition(.numericText())
                    } else {
                        Image(systemName: unchecked ? "questionmark" : "checkmark")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(unchecked ? Color.secondary : Color.green)
                    }
                }
            VStack(alignment: .leading, spacing: 6) {
                Text(headline(issues: issues, unchecked: unchecked))
                    .font(.system(size: 22, weight: .semibold))
                Text(subline(issues: issues))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button(model.checkingLeaks ? "Looking…" : "Check Now") { Task { await model.checkForLeaks() } }
                        .glassProminentButton()
                        .disabled(model.checkingLeaks)
                    Text(lastChecked).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(in: .rect(cornerRadius: 22))
    }

    private func headline(issues: Int, unchecked: Bool) -> String {
        if model.checkingLeaks { return "Looking…" }
        if issues == 1 { return "1 thing to look at" }
        if issues > 1 { return "\(issues) things to look at" }
        return unchecked ? "Not checked yet" : "All good"
    }

    private func subline(issues: Int) -> String {
        if model.checkingLeaks { return "Looking for copies of your saved values in your projects, their git history, AI conversations and shell history." }
        if issues > 0 { return "Each one below says why it matters and what to do." }
        return "Slinky looks for copies of your saved values left in files, and for anything that needs you, like a key about to expire."
    }

    private var lastChecked: String {
        guard let d = model.leaksChecked else { return model.checkingLeaks ? "" : "Not checked since unlocking" }
        return "Checked \(d.formatted(.relative(presentation: .named)))"
    }
}

/// A ring of segments, one per check, colored by how each went. Turns slowly while a check runs.
private struct HealthRing: View {
    let checks: [HealthCheck]
    var spinning: Bool
    @State private var turn = 0.0

    var body: some View {
        let n = max(checks.count, 1)
        let gap = 0.018
        ZStack {
            ForEach(Array(checks.enumerated()), id: \.element.id) { i, check in
                Circle()
                    .trim(from: Double(i) / Double(n) + gap, to: Double(i + 1) / Double(n) - gap)
                    .stroke(color(check), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy, value: check.status)
            }
        }
        .padding(5)
        .rotationEffect(.degrees(turn))
        .onChange(of: spinning, initial: true) { _, now in
            if now {
                withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { turn = 360 }
            } else {
                withAnimation(.snappy) { turn = 0 }
            }
        }
        .accessibilityHidden(true)
    }

    private func color(_ check: HealthCheck) -> Color {
        switch check.status {
        case .clear: .green.opacity(0.85)
        case .found: .orange
        case .notChecked, .checking, .nothingToCheck: .secondary.opacity(0.25)
        }
    }
}

/// One check: what it looked at and what it found. A tile with something found takes you to it.
private struct HealthTile: View {
    let check: HealthCheck
    let show: () -> Void

    var body: some View {
        let found: Bool = if case .found = check.status { true } else { false }
        Button(action: show) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: check.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(found ? Color.orange : Color.accentColor)
                        .frame(width: 30, height: 30)
                        .background((found ? Color.orange : Color.accentColor).opacity(0.13), in: .rect(cornerRadius: 8, style: .continuous))
                    Spacer()
                    status
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(check.title).font(.headline)
                    Text(check.scope).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(Color.paper.opacity(0.6), in: .rect(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(found ? Color.orange.opacity(0.45) : Color.secondary.opacity(0.16), lineWidth: 1))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(!found)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var status: some View {
        switch check.status {
        case .clear:
            Label("Clear", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        case let .found(n):
            Text("\(n) found")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.orange, in: .capsule)
        case .checking:
            ProgressView().controlSize(.mini)
        case .notChecked:
            Text("Not checked").font(.caption).foregroundStyle(.secondary)
        case .nothingToCheck:
            Text("None linked").font(.caption).foregroundStyle(.tertiary)
        }
    }
}

/// A finding: why it matters, and its fix.
private struct HealthRow<Actions: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    /// A file's place, on its own line, cut in the middle so the file name always shows.
    var path: String? = nil
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 32, height: 32).background(tint.opacity(0.14), in: .rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).lineLimit(2)
                Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                if let path {
                    Text(path).font(.caption.monospaced()).foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.middle).help(path)
                }
            }
            Spacer(minLength: 8)
            actions
        }
        .padding(12)
        .glass(in: .rect(cornerRadius: 14))
    }
}

private struct AttentionRow: View {
    @Environment(AppModel.self) private var model
    let item: AttentionItem
    let show: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 32, height: 32)
                .background(Color.orange.opacity(0.14), in: .rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.headline)
                Text(item.detail).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            if let id = item.recoveryKeyID, let kept = model.document.kept.first(where: { $0.id == id }) {
                Button("I Have a Copy") { model.markPrinted(id) }
                    .help("You've saved it somewhere else, like on paper or in Apple Passwords")
                Button("Print…") {
                    RecoveryPrinter.print(kept.value, title: kept.label)
                    model.markPrinted(id)
                }
                .glassProminentButton()
            } else {
                Button("Show", action: show)
            }
        }
        .padding(12)
        .glass(in: .rect(cornerRadius: 14))
    }
}

/// Search from the sidebar field: every key, variable, code set and recovery key, by name.
struct SearchResultsView: View {
    @Environment(AppModel.self) private var model
    let query: String

    private var results: [QuickItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return model.quickItems.filter { $0.title.lowercased().contains(q) || $0.subtitle.lowercased().contains(q) }
    }

    var body: some View {
        let results = results
        Group {
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(results) { item in
                    HStack(spacing: 10) {
                        ServiceIcon(subject: item.icon, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.system(size: 13, weight: .medium, design: item.mono ? .monospaced : .default))
                                .lineLimit(1)
                            Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if item.isLive { Chip(text: "LIVE", style: .live) }
                        Button("Show") { show(item) }
                        CopyButton { copy(item) }
                    }
                    .padding(.vertical, 3)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .screenTitle("Search", subtitle: "\(results.count) \(results.count == 1 ? "result" : "results")")
    }

    private func copy(_ item: QuickItem) {
        if case let .codes(setID) = item.kind, let index = model.document.codeSets.first(where: { $0.id == setID })?.nextUnused {
            model.useCode(index, in: setID)
        } else {
            model.copy(item.value, label: item.title)
        }
    }

    private func show(_ item: QuickItem) {
        switch item.kind {
        case let .variable(project, _): model.selection = .project(project)
        case .key:
            model.selection = .library(.keys)
            model.librarySelection = UUID(uuidString: item.id).map(LibraryRef.key)
        case .kept:
            model.selection = .library(.recovery)
            model.librarySelection = UUID(uuidString: item.id).map(LibraryRef.kept)
        case let .codes(id):
            model.selection = .library(.recovery)
            model.librarySelection = .codes(id)
        }
        model.searchText = ""
    }
}
