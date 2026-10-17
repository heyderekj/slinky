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
                    Label(filter.title, systemImage: filter.symbol)
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
                    }
                    .badge(attention.count)
                    .tag(SidebarItem.attention)
                    .transition(.opacity)
                }
            }
            Section {
                if model.document.projects.isEmpty {
                    ProjectsEmptyCard()
                        .selectionDisabled()
                        .listRowSeparator(.hidden)
                }
                ForEach(model.document.projects) { project in
                    projectRow(project)
                }
            } header: {
                Text("Projects")
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

    /// One labeled action, like Notes' "New Folder". Items are added from the toolbar's Add Item.
    private var footer: some View {
        HStack {
            Button {
                model.showNewProject = true
            } label: {
                Label("New Project", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("New Project (⇧⌘N)")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func count(_ filter: LibraryFilter) -> Int {
        switch filter {
        case .all: model.document.keys.count + model.document.codeSets.count + model.document.kept.count
        case .keys: model.document.keys.count
        case .recovery: model.document.codeSets.count + model.document.kept.count
        }
    }
}

/// The sidebar's welcome for projects: what a project is, with a drop zone that makes one.
struct ProjectsEmptyCard: View {
    @Environment(AppModel.self) private var model
    @State private var targeted = false

    private let examples = ["DATABASE_URL", "STRIPE_SECRET_KEY", "OPENAI_API_KEY"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // A small preview of what a project holds: its .env, with values hidden.
            VStack(alignment: .leading, spacing: 4) {
                ForEach(examples, id: \.self) { name in
                    HStack(spacing: 0) {
                        Text(name).foregroundStyle(.secondary)
                        Text("=••••").foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.paper.opacity(0.6), in: .rect(cornerRadius: 8))

            // Sidebar rows default to one line; these need to wrap.
            Text("Keep each app's .env variables together, out of the project folder.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            Text("Drop a project folder or .env file here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.35),
                              style: StrokeStyle(lineWidth: targeted ? 1.5 : 1, dash: [4, 3]))
                .background(targeted ? Color.accentColor.opacity(0.1) : .clear, in: .rect(cornerRadius: 12))
        }
        .animation(.smooth(duration: 0.2), value: targeted)
        .padding(.vertical, 4)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in model.createProject(dropped: url) }
                }
            }
            return true
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
