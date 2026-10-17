import SlinkyCoreShared
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 236, max: 300)
        } detail: {
            switch model.selection {
            case let .project(id)?:
                ProjectView(projectID: id).id(id)
            case let .library(filter)?:
                LibraryView(filter: filter)
            case nil:
                LibraryView(filter: .kept)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.tuckPrefill = ""
                    model.tuckProject = nil
                    model.showTuck = true
                } label: {
                    Label("Tuck It Away", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.glassProminent)
                .help("Paste anything. Slinky figures out where it goes. ⌘N")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { model.lock(reason: .manual) } label: { Label("Lock", systemImage: "lock") }
                    .help("Lock Slinky ⌃⌘L")
            }
        }
        .sheet(isPresented: $model.showTuck) { TuckItAwayView() }
        .sheet(isPresented: $model.showNewProject) { NewProjectView() }
        .sheet(isPresented: Binding(get: { model.recoveryKeyToShow != nil && !model.showTuck },
                                    set: { if !$0 { model.recoveryKeyToShow = nil } })) {
            if let key = model.recoveryKeyToShow { RecoveryKeySheet(key: key) }
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Section {
                HStack(spacing: 6) {
                    ForEach(LibraryFilter.allCases, id: \.self) { filter in
                        CategoryTile(filter: filter, count: count(filter), selected: model.selection == .library(filter)) {
                            model.selection = .library(filter)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 8, trailing: 6))
                .listRowBackground(Color.clear)
            }
            Section("Projects") {
                ForEach(model.document.projects) { project in
                    Label(project.name, systemImage: "folder")
                        .badge(project.missing.isEmpty ? Text("\(project.variables.count)") : Text("\(project.missing.count) missing").foregroundStyle(.orange))
                        .tag(SidebarItem.project(project.id))
                        .contextMenu {
                            Button("Remove Project", role: .destructive) { model.deleteProject(project.id) }
                        }
                }
                Button {
                    model.showNewProject = true
                } label: {
                    Label("New Project…", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Text(model.hasVault ? "\(model.document.secretCount) secrets · \(model.document.projects.count) projects · 0 lying around" : "No vault yet. It appears with your first secret.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
    }

    private func count(_ filter: LibraryFilter) -> Int {
        switch filter {
        case .keys: model.document.keys.count
        case .codes: model.document.codeSets.count
        case .kept: model.document.kept.count
        }
    }
}

/// Apple Reminders-style tile with a count.
struct CategoryTile: View {
    var filter: LibraryFilter
    var count: Int
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: filter.symbol)
                        .foregroundStyle(selected ? Color.white : Color.accentColor)
                    Spacer()
                    Text("\(count)")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                }
                Text(filter.title).font(.caption).foregroundStyle(selected ? Color.white.opacity(0.9) : Color.secondary)
            }
            .padding(9)
            .frame(maxWidth: .infinity)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.background.secondary), in: .rect(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.separator.opacity(selected ? 0 : 0.5), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filter.title), \(count)")
    }
}

struct NewProjectView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var folder: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New project").font(.headline)
            TextField("Name, like harvous", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Text(folder?.path(percentEncoded: false) ?? "No folder linked yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                Button("Choose Folder…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.prompt = "Link"
                    if panel.runModal() == .OK, let url = panel.url {
                        folder = url
                        if name.isEmpty { name = url.lastPathComponent }
                    }
                }
            }
            Text("Linking the folder lets Slinky read its .env.example and spot missing keys. Slinky never writes into it.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    model.createProject(name: name.trimmingCharacters(in: .whitespaces), folder: folder)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 460)
    }
}
