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
                LibraryView(filter: .all)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.tuckPrefill = ""
                    model.tuckProject = nil
                    model.showTuck = true
                } label: {
                    Label("Add Item", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.glassProminent)
                .help("Add a key, a project variable, recovery codes or a recovery key (⌘N)")
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
            Section("Library") {
                ForEach(LibraryFilter.allCases, id: \.self) { filter in
                    Label {
                        Text(filter.title)
                    } icon: {
                        Image(systemName: filter.symbol)
                            .symbolEffect(.bounce, value: model.selection == .library(filter))
                    }
                    .badge(count(filter))
                        .tag(SidebarItem.library(filter))
                }
            }
            Section("Projects") {
                if model.document.projects.isEmpty {
                    Text("No projects")
                        .foregroundStyle(.tertiary)
                        .selectionDisabled()
                }
                ForEach(model.document.projects) { project in
                    Label(project.name, systemImage: "folder")
                        .badge(project.variables.count)
                        .tag(SidebarItem.project(project.id))
                        .contextMenu {
                            Button("Delete Project", role: .destructive) { model.deleteProject(project.id) }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Menu {
                    Button("New Item…") {
                        model.tuckPrefill = ""
                        model.tuckProject = nil
                        model.showTuck = true
                    }
                    Button("New Project…") { model.showNewProject = true }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Add an item or a project")
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func count(_ filter: LibraryFilter) -> Int {
        switch filter {
        case .all: model.document.keys.count + model.document.codeSets.count + model.document.kept.count
        case .keys: model.document.keys.count
        case .recovery: model.document.codeSets.count + model.document.kept.count
        }
    }
}

struct NewProjectView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var folder: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Project").font(.headline)
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
            Text("If you link the project folder, Slinky reads its .env.example to show which variables are missing. Slinky never changes files in it.")
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
