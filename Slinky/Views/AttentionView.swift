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
                title: set.remaining == 0 ? "No \(set.account) codes left" : "Only \(set.remaining) \(set.account) codes left",
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

/// Health: saved values found outside Slinky, what needs a person, and tidying up.
struct AttentionView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmHistory: LeakFinding?
    @State private var confirmMove: LeakFinding?

    var body: some View {
        let items = model.attention
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                leaksSection
                if !items.isEmpty {
                    section("Needs you") {
                        ForEach(items) { item in AttentionRow(item: item) { model.selection = item.target } }
                    }
                }
                tidySection
                if items.isEmpty, model.leaks.isEmpty, model.unusedKeys.isEmpty, model.duplicates.isEmpty, !model.checkingLeaks {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, Color.green).font(.title2)
                        Text("All good. Slinky lets you know here when something needs you.").foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(18)
            .frame(maxWidth: .infinity)
        }
        .screenTitle("Health", subtitle: model.healthCount == 0 ? "All good" : "\(model.healthCount) to look at")
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

    private var leaksSection: some View {
        section("Secrets outside Slinky", trailing: {
            HStack(spacing: 8) {
                if model.checkingLeaks { ProgressView().controlSize(.small) }
                Text(model.checkingLeaks ? "Looking…" : lastChecked).font(.caption).foregroundStyle(.secondary)
                Button("Check Now") { Task { await model.checkForLeaks() } }.disabled(model.checkingLeaks).controlSize(.small)
            }
        }) {
            if model.leaks.isEmpty {
                Text(model.checkingLeaks ? "Looking in your projects, their git history, AI conversations and shell history…"
                                         : "None found in linked projects, their git history, AI conversations or shell history.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(model.leaks) { finding in
                HStack(spacing: 12) {
                    Image(systemName: symbol(finding)).font(.system(size: 16, weight: .semibold)).foregroundStyle(.orange)
                        .frame(width: 32, height: 32).background(Color.orange.opacity(0.14), in: .rect(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(finding.title).font(.headline).lineLimit(2)
                        Text(finding.detail).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                    }
                    Spacer(minLength: 8)
                    actions(finding)
                }
                .padding(12)
                .glass(in: .rect(cornerRadius: 14))
            }
        }
    }

    @ViewBuilder
    private func actions(_ f: LeakFinding) -> some View {
        switch f.place {
        case .envFile:
            Button("Move into Slinky") { confirmMove = f }.glassProminentButton()
        case .history:
            Button("Remove Lines…") { confirmHistory = f }.glassProminentButton()
        default:
            Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f.path)]) }
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
            section("Tidy up") {
                if !unused.isEmpty {
                    tidyRow("clock", "Not used in over 60 days: \(unused.prefix(3).map(\.name).joined(separator: ", "))\(unused.count > 3 ? " and \(unused.count - 3) more" : "")",
                            "If you don't need them any more, delete them here and revoke them on the service.") { model.selection = .library(.keys) }
                }
                ForEach(dupes, id: \.self) { names in
                    tidyRow("square.on.square", "Saved twice: \(names.joined(separator: " and "))",
                            "Same value in two places. Keeping one makes replacing it later simpler.") { model.selection = .library(.all) }
                }
            }
        }
    }

    private func tidyRow(_ symbol: String, _ title: String, _ detail: String, show: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary).frame(width: 32, height: 32)
                .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).lineLimit(2)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Show", action: show)
        }
        .padding(12)
        .glass(in: .rect(cornerRadius: 14))
    }

    private var lastChecked: String {
        let d = Preferences.shared.lastLeakCheck
        return d == .distantPast ? "Not checked yet" : "Checked \(d.formatted(.relative(presentation: .named)))"
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        section(title, trailing: { EmptyView() }, content: content)
    }

    private func section<Trailing: View, Content: View>(_ title: String, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline).foregroundStyle(.secondary)
                Spacer()
                trailing()
            }
            content()
        }
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
