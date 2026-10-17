import SlinkyCoreShared
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            if model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                detail
            } else {
                SearchResultsView(query: model.searchText)
            }
        }
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search")
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

    @ViewBuilder
    private var detail: some View {
        switch model.selection {
        case let .project(id)?:
            ProjectView(projectID: id).id(id)
        case let .library(filter)?:
            LibraryView(filter: filter)
        case .attention?:
            AttentionView()
        case nil:
            LibraryView(filter: .all)
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var dropTarget: UUID?

    var body: some View {
        @Bindable var model = model
        let attention = model.attention
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
                // Only there when something needs a person to act.
                if !attention.isEmpty || model.selection == .attention {
                    Label {
                        Text("Needs Attention")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .symbolEffect(.wiggle, value: attention.count)
                    }
                    .badge(attention.count)
                    .tag(SidebarItem.attention)
                    .transition(.opacity)
                }
            }
            Section {
                if model.document.projects.isEmpty {
                    Text("No projects")
                        .foregroundStyle(.tertiary)
                        .selectionDisabled()
                }
                ForEach(model.document.projects) { project in
                    projectRow(project)
                }
            } header: {
                HStack {
                    Text("Projects")
                    Spacer()
                    Button { model.showNewProject = true } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                        .help("New Project (⇧⌘N)")
                }
            }
        }
        .listStyle(.sidebar)
        .animation(.smooth, value: attention.isEmpty)
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
    }

    private func projectRow(_ project: Project) -> some View {
        let missing = project.missing.count
        return Label {
            Text(project.name)
        } icon: {
            Monogram(text: project.name, size: 18)
        }
        .badge(missing > 0 ? Text("\(missing) missing").foregroundStyle(.orange) : Text("\(project.variables.count)"))
        .tag(SidebarItem.project(project.id))
        .listRowBackground(dropTarget == project.id ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.18)) : nil)
        .help(missing > 0 ? "\(project.name) is missing \(missing) variables" : "Drop a .env file here to import it")
        .onDrop(of: [.fileURL], isTargeted: Binding(get: { dropTarget == project.id },
                                                    set: { dropTarget = $0 ? project.id : (dropTarget == project.id ? nil : dropTarget) })) { providers in
            drop(providers, on: project.id)
        }
        .contextMenu {
            if let folder = project.folders.first {
                Button("Show Folder in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)])
                }
                Divider()
            }
            Button("Delete Project", role: .destructive) { model.deleteProject(project.id) }
        }
    }

    /// A .env file dropped on a project imports into Local; a folder links it.
    private func drop(_ providers: [NSItemProvider], on projectID: UUID) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                        model.linkFolder(url, to: projectID)
                    } else {
                        model.importEnvFile(url, into: projectID, env: .local)
                    }
                    model.selection = .project(projectID)
                }
            }
        }
        return true
    }

    private var footer: some View {
        HStack(spacing: 8) {
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
            if model.hasVault {
                Label("Encrypted on this Mac", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .labelStyle(.titleAndIcon)
                    .help("Everything in Slinky is encrypted and stays on this Mac. It locks when you lock your screen, after 10 minutes away, or when you press ⌃⌘L.")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
