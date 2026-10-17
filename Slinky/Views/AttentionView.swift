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

struct AttentionView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let items = model.attention
        Group {
            if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.green)
                    Text("Nothing needs attention").font(.title2.weight(.bold))
                    Text("Slinky lets you know here when codes run low, a project is missing variables or a key is about to expire.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 330)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(items) { item in
                            AttentionRow(item: item) { model.selection = item.target }
                        }
                    }
                    .frame(maxWidth: 620)
                    .padding(18)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Needs Attention")
        .navigationSubtitle(items.isEmpty ? "" : "\(items.count) \(items.count == 1 ? "item" : "items")")
    }
}

private struct AttentionRow: View {
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
            Button("Show", action: show)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
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
                        Monogram(text: item.provider ?? item.title, size: 26)
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
        .navigationTitle("Search")
        .navigationSubtitle("\(results.count) \(results.count == 1 ? "result" : "results")")
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
        case .key: model.selection = .library(.keys)
        case .kept, .codes: model.selection = .library(.recovery)
        }
        model.searchText = ""
    }
}
