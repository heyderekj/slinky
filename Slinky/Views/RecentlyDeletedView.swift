import SlinkyCoreShared
import SwiftUI

/// Recently Deleted: everything removed in the last 30 days, ready to put back.
struct RecentlyDeletedView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmEmpty = false
    @State private var confirmDelete: TrashEntry?

    var body: some View {
        let entries = model.document.trashed
        Group {
            if entries.isEmpty {
                ContentUnavailableView("Nothing here", systemImage: "trash",
                                       description: Text("Things you delete wait here for 30 days, so you can put them back."))
            } else {
                List {
                    ForEach(entries) { entry in row(entry) }
                    // A plain row, not a section footer: footers stick to the edge and get a second line from macOS.
                    Text("Items here are deleted for good after 30 days.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                        .listRowSeparator(.hidden)
                        .selectionDisabled()
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .screenTitle("Recently Deleted", subtitle: entries.isEmpty ? "" : "\(entries.count) \(entries.count == 1 ? "item" : "items")")
        .toolbar {
            if !entries.isEmpty, !model.lockedChrome {
                ToolbarItem {
                    Button("Empty") { confirmEmpty = true }
                        .help("Delete everything here for good")
                }
            }
        }
        .confirmationDialog("Delete everything in Recently Deleted?", isPresented: $confirmEmpty) {
            Button("Delete \(entries.count) \(entries.count == 1 ? "Item" : "Items")", role: .destructive) { model.emptyTrash() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .confirmationDialog("Delete \(confirmDelete?.item.title ?? "this") for good?",
                            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            presenting: confirmDelete) { entry in
            Button("Delete", role: .destructive) { model.deleteNow(entry.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    private func row(_ entry: TrashEntry) -> some View {
        HStack(spacing: 12) {
            ServiceIcon(subject: subject(entry.item), size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.item.title).font(.system(size: 13, weight: .semibold))
                    .lineLimit(2).truncationMode(.middle).help(entry.item.title)
                Text("\(kind(entry.item)) · \(Self.goesIn(entry))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            Button("Restore") { model.restore(entry.id) }
                .glassButton()
                .controlSize(.small)
                .fixedSize()
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Restore") { model.restore(entry.id) }
            Divider()
            Button("Delete Now…", role: .destructive) { confirmDelete = entry }
        }
    }

    private func kind(_ item: TrashedItem) -> String {
        switch item {
        case .key: "Key or token"
        case .codes: "Recovery codes"
        case .kept(let k): k.kind.title
        case .file(let f): f.kind.title
        case .variable(_, _, let project): "Variable in \(project)"
        case .project(let p): "Project · \(p.variables.count) \(p.variables.count == 1 ? "variable" : "variables")"
        }
    }

    private func subject(_ item: TrashedItem) -> IconSubject {
        switch item {
        case .key(let k): k.iconSubject
        case .codes(let c): c.iconSubject
        case .kept(let k): k.iconSubject
        case .file(let f): f.iconSubject
        case .variable(let v, _, _): v.iconSubject
        case .project(let p): IconSubject(name: p.name, choice: .monogram)
        }
    }
}

extension RecentlyDeletedView {
    /// When it's deleted for good, which is the thing worth knowing: "Deleted for good in 3 days", "…tomorrow".
    static func goesIn(_ entry: TrashEntry, now: Date = .now) -> String {
        let end = entry.deletedAt.addingTimeInterval(Double(VaultDocument.trashDays) * 86_400)
        let days = Int((end.timeIntervalSince(now) / 86_400).rounded(.up))
        switch days {
        case ...0: return "Deleted for good today"
        case 1: return "Deleted for good tomorrow"
        default: return "Deleted for good in \(days) days"
        }
    }
}
