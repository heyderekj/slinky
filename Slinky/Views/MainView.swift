import SlinkyCoreShared
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
                // The built-in toggle lives in the sidebar's part of the toolbar. While the sidebar opens
                // or closes that part is too narrow for it, so macOS shows the overflow » for a moment.
                .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                if model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    detail
                } else {
                    SearchResultsView(query: model.searchText)
                }
            }
            .overlay(alignment: .bottom) { ToastView() }
            .toolbar {
                // Our own toggle, in the content's part of the toolbar (like Dinky), so it never gets squeezed.
                ToolbarItem(placement: .navigation) {
                    Button {
                        withAnimation(.spring(duration: 0.35)) { columns = columns == .detailOnly ? .all : .detailOnly }
                    } label: {
                        Label("Sidebar", systemImage: "sidebar.left")
                    }
                    .help(columns == .detailOnly ? "Show the sidebar (⌃⌘S)" : "Hide the sidebar (⌃⌘S)")
                    .accessibilityLabel(columns == .detailOnly ? "Show sidebar" : "Hide sidebar")
                    .disabled(model.lockedChrome)
                }
                // Always here, whatever's on screen: in a project it adds a variable to that project.
                ToolbarItem(placement: .primaryAction) {
                    Button { addHere() } label: { Label("Add Item", systemImage: "plus") }
                        .help(isProject ? "Add a variable to this project (⌘N)" : "Add Item (⌘N)")
                        .disabled(model.lockedChrome)
                }
            }
            // Drop a key or some .env lines anywhere on the content to add them.
            .dropDestination(for: String.self) { items, _ in
                // A file dragged from Finder also arrives as its path. Files aren't items, so leave those alone.
                guard let text = items.first, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !text.hasPrefix("/"), !text.hasPrefix("file://"), canAdd else { return false }
                addHere(prefill: text)
                return true
            }
        }
        // The locked window has no sidebar, so it slides away as locking starts (this window is gone once the vault
        // locks). Unlocking never hides it: a split view that starts without its sidebar lays it out clipped when it
        // slides in, so the sidebar is simply there under the opening keyhole.
        .onChange(of: model.curtain) { _, curtain in
            if curtain == .closing {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { columns = .detailOnly }
            }
        }
        .background(PasteToAdd { text in
            guard canAdd else { return false }
            addHere(prefill: text)
            return true
        })
        .overlay {
            if model.showTuck {
                AddItemOverlay().transition(.opacity)
            } else if model.showNewProject {
                NewProjectOverlay().transition(.opacity)
            } else if let target = model.editing {
                EditOverlay(target: target).transition(.opacity)
            } else if let result = model.importing {
                ImportOverlay(result: result).transition(.opacity)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: model.showTuck)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: model.showNewProject)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: model.editing)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: model.importing != nil)
        .sheet(isPresented: $model.showRestore) { RestoreBackupView() }
        .sheet(isPresented: Binding(get: { model.choosingIcon != nil }, set: { if !$0 { model.choosingIcon = nil } })) {
            if let ref = model.choosingIcon { ChooseIconView(ref: ref) }
        }
        .sheet(isPresented: Binding(get: { model.recoveryKeyToShow != nil && !model.showTuck },
                                    set: { if !$0 { model.recoveryKeyToShow = nil } })) {
            if let key = model.recoveryKeyToShow { RecoveryKeySheet(key: key) }
        }
    }

    private var isProject: Bool { if case .project? = model.selection { true } else { false } }

    /// Nothing else is open on top, so adding makes sense right now.
    private var canAdd: Bool {
        model.isUnlocked && !model.showTuck && !model.showNewProject && model.editing == nil && model.importing == nil
    }

    private func addHere(prefill: String = "") {
        if case let .project(id)? = model.selection { model.openAddItem(prefill: prefill, project: id) }
        else { model.openAddItem(prefill: prefill) }
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
        case .trash?:
            RecentlyDeletedView()
        case nil:
            LibraryView(filter: .all)
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var dropTarget: UUID?
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var model = model
        let attention = model.attention
        List(selection: $model.selection) {
            // The top group needs no heading (like Passwords and Notes). Projects keeps its own.
            Section {
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
                // Only there when something's waiting to be restored.
                if !model.document.trashed.isEmpty || model.selection == .trash {
                    Label("Recently Deleted", systemImage: "trash")
                        .badge(model.document.trashed.count)
                        .tag(SidebarItem.trash)
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
        // Our own search field. The built-in one moves into the toolbar when the sidebar hides,
        // and overflows (») while the sidebar animates.
        .safeAreaInset(edge: .top, spacing: 0) {
            SidebarSearchField(text: $model.searchText, focused: $searchFocused)
                .padding(.horizontal, 10)
                .padding(.top, 2)
                .padding(.bottom, 6)
        }
        .onAppear {
            // macOS hands focus to the first text field when the window opens. Search shouldn't take it.
            DispatchQueue.main.async { searchFocused = false }
        }
        .background {
            Button("Find") { searchFocused = true }
                .keyboardShortcut("f")
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
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
            Button("Edit Project…") { model.editing = .project(project.id) }
            Divider()
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

    /// One labeled action, like Notes' "New Folder". Items are added from the toolbar's Add button (⌘N).
    private var footer: some View {
        VStack(spacing: 0) {
            if Updater.shared.shouldShowBanner {
                UpdateBanner()
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            footerRow
        }
        .animation(.smooth, value: Updater.shared.shouldShowBanner)
    }

    private var footerRow: some View {
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

/// "Slinky 1.1 is available" at the bottom of the sidebar, like Dinky's update banner.
struct UpdateBanner: View {
    private var updater: Updater { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Slinky \(updater.availableVersion ?? "") is available").font(.callout.weight(.semibold))
                    switch updater.installState {
                    case .downloading: Text("Downloading…").font(.caption).foregroundStyle(.secondary)
                    case .installing: Text("Installing…").font(.caption).foregroundStyle(.secondary)
                    case let .failed(message): Text(message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    case .idle: Text("You're on \(updater.currentVersion).").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                IconButton(symbol: "xmark", help: "Not now") { updater.dismissBanner() }
            }
            HStack(spacing: 8) {
                Button("Install") { Task { await updater.install() } }
                    .glassProminentButton()
                    .controlSize(.small)
                    .disabled(updater.installState == .downloading || updater.installState == .installing)
                if let url = updater.releaseURL {
                    Link("What's New", destination: url).font(.caption)
                }
            }
        }
        .padding(12)
        .glass(in: .rect(cornerRadius: 14))
    }
}

/// Looks like the system search field: a capsule with a magnifying glass, a clear button, Esc to clear.
struct SidebarSearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("", text: $text, prompt: Text("Search"))
                .textFieldStyle(.plain)
                .focused(focused)
                .onExitCommand { text = "" }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color.primary.opacity(0.07), in: Capsule())
        .overlay(Capsule().strokeBorder(focused.wrappedValue ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search Slinky")
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
                    Task { @MainActor in model.startProject(dropped: url) }
                }
            }
            return true
        }
    }
}
