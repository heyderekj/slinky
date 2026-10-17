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
                    Section {
                        ForEach(entries) { entry in row(entry) }
                    } footer: {
                        Text("Items here are deleted for good after 30 days.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationSubtitle(entries.isEmpty ? "" : "\(entries.count) \(entries.count == 1 ? "item" : "items")")
        .toolbar {
            if !entries.isEmpty {
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
            Monogram(text: monogramText(entry.item), size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.item.title).font(.system(size: 13, weight: .semibold))
                Text("\(kind(entry.item)) · Deleted \(entry.deletedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Restore") { model.restore(entry.id) }
                .glassButton()
                .controlSize(.small)
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
        case .variable(_, _, let project): "Variable in \(project)"
        case .project(let p): "Project · \(p.variables.count) \(p.variables.count == 1 ? "variable" : "variables")"
        }
    }

    private func monogramText(_ item: TrashedItem) -> String {
        switch item {
        case .key(let k): k.provider ?? k.name
        case .codes(let c): c.account
        case .kept(let k): k.from ?? k.label
        case .variable(let v, _, _): v.provider ?? v.name
        case .project(let p): p.name
        }
    }
}
