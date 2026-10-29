import SlinkyCoreShared
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    /// The window's undo manager: Slinky's one undo step goes on it, so Edit › Undo and ⌘Z work.
    @Environment(\.undoManager) private var undoManager
    // Never animated around locking: the split view's column animation stuttered over the keyhole. Unlocking
    // reveals the window with its sidebar already in place; locking leaves it until the curtain has covered it.
    @State private var columns: NavigationSplitViewVisibility = .all
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView()
                // The built-in toggle lives in the sidebar's part of the toolbar. While the sidebar opens
                // or closes that part is too narrow for it, so macOS shows the overflow » for a moment.
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 320)
        } detail: {
            Group {
                if model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    detail
                } else {
                    SearchResultsView(query: model.searchText).shrinkable()
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
                // Always somewhere, whatever's on screen. The library and projects put it in a group with their
                // own buttons (like Passwords' sort and +), so it's only here for the other screens.
                if !screenHasOwnAdd {
                    ToolbarItem(placement: .primaryAction) { AddItemButton() }
                }
            }
            // Files dropped on the content: an export opens Import, a folder or .env file the folder review, a key file
            // (.p8, .pem, service-account JSON) is kept in the vault. Projects take their own drops.
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard canAdd, !isProject else { return false }
                Task { model.open(await AppModel.urls(from: providers), on: .window) }
                return true
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
        // Search sits at the right end of the toolbar, like Passwords. It searches names, never values.
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search")
        .searchFocused($searchFocused)
        .background {
            Button("Find") { searchFocused = true }
                .keyboardShortcut("f")
                .disabled(model.panelOpen)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .background(ToolbarFader(hidden: model.panelOpen))
        .onAppear { model.windowUndoManager = undoManager }
        .onChange(of: undoManager) { _, manager in model.windowUndoManager = manager }
        .background(PasteToAdd { text in
            guard canAdd else { return false }
            addHere(prefill: text)
            return true
        })
        .overlay {
            if model.showTuck {
                AddItemOverlay().transition(.opacity)
            } else if let review = model.review {
                FolderReviewOverlay(review: review).id(review.id).transition(.opacity)
            } else if let target = model.editing {
                EditOverlay(target: target).transition(.opacity)
            } else if let result = model.importing {
                ImportOverlay(result: result).transition(.opacity)
            } else if let draft = model.sharing {
                ShareOverlay(draft: draft).id(draft.id).transition(.opacity)
            } else if let share = model.receiving {
                ReceiveOverlay(share: share).id(share.id).transition(.opacity)
            } else if let draft = model.addingPerson {
                AddPersonOverlay(draft: draft).id(draft.id).transition(.opacity)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: model.showTuck)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: model.review)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: model.editing)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: model.importing != nil)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: model.sharing)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: model.receiving)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: model.addingPerson)
        .sheet(item: Binding(get: { SharedProjects.shared.checklist }, set: { SharedProjects.shared.checklist = $0 })) {
            RotationChecklistSheet(checklist: $0)
        }
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

    private var screenHasOwnAdd: Bool {
        guard model.searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch model.selection {
        case .library?, .project?, nil: return true
        default: return false
        }
    }

    /// Nothing else is open on top, so adding makes sense right now.
    private var canAdd: Bool {
        model.isUnlocked && !model.panelOpen
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
            AttentionView().shrinkable()
        case .trash?:
            RecentlyDeletedView().shrinkable()
        case .activity?:
            ActivityView().shrinkable()
        case .people?:
            PeopleView().shrinkable()
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
        List(selection: $model.selection) {
            // The places, as tiles with counts (like Passwords). Not rows, so the list's selection skips them.
            Section {
                CategoryGrid()
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 10, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .selectionDisabled()
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
                ProjectsHeader()
            }
        }
        .listStyle(.sidebar)
        // A folder or .env file dropped on the sidebar's empty space makes a new project too (rows and the
        // Projects heading take their own drops first).
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard model.isUnlocked, !model.panelOpen else { return false }
            Task { model.open(await AppModel.urls(from: providers), on: .projects) }
            return true
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
    }

    private func projectRow(_ project: Project) -> some View {
        let missing = project.missing.count
        return Label {
            Text(project.name)
        } icon: {
            Monogram(text: project.name, size: 18)
                .overlay(alignment: .bottomTrailing) {
                    if project.sharing != nil {
                        Image(systemName: "person.2.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white, Color.accentColor)
                            .offset(x: 4, y: 4)
                            .accessibilityLabel("Shared")
                    }
                }
        }
        .badge(missing > 0 ? Text("\(missing) missing").foregroundStyle(Color.attention) : Text("\(project.variables.count)"))
        .tag(SidebarItem.project(project.id))
        .listRowBackground(dropTarget == project.id ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.18)) : nil)
        .help(missing > 0 ? "\(project.name) is missing \(counted(missing, "variable"))" : "Drop a .env file or the project folder here to update it")
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
            Button(project.folders.isEmpty ? "Link Folder…" : "Update from Folder…") { model.updateFromFolder(project.id) }
            Button("Edit Project…") { model.editing = .project(project.id) }
            Divider()
            Button("Delete Project", role: .destructive) { model.deleteProject(project.id) }
        }
    }

    /// A folder or .env file dropped on a project opens the review of what it would change there.
    private func drop(_ providers: [NSItemProvider], on projectID: UUID) -> Bool {
        Task {
            let urls = await AppModel.urls(from: providers)
            model.selection = .project(projectID)
            model.open(urls, on: .project(projectID))
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
                model.review = FolderReview(target: .newProject)
            } label: {
                Label("New Project", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("New Project (⇧⌘N)")
            .disabled(model.panelOpen)
            Spacer()
            // The people you share with: a quiet footer button like Activity's, cyan while showing.
            Button {
                model.selection = .people
            } label: {
                Label("People", systemImage: "person.2")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(model.selection == .people ? Color.accentColor : .secondary)
            .help("People: share keys and projects with the people you work with")
            .accessibilityAddTraits(model.selection == .people ? .isSelected : [])
            .padding(.trailing, 6)
            // A history, not a kind of item or a place: a quiet button in the footer, like Notes' footer actions,
            // rather than a row or a tile. Cyan while it's showing.
            Button {
                model.selection = .activity
            } label: {
                Label("Activity", systemImage: "clock.arrow.circlepath")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(model.selection == .activity ? Color.accentColor : .secondary)
            .help("Activity: what was copied or used, and by whom")
            .accessibilityAddTraits(model.selection == .activity ? .isSelected : [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// The toolbar's +. In a project it adds a variable to that project.
struct AddItemButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            if case let .project(id)? = model.selection { model.openAddItem(project: id) }
            else if model.selection == .people { model.beginAddPerson() }
            else { model.openAddItem() }
        } label: {
            Label("Add Item", systemImage: "plus")
        }
        .help(isProject ? "Add a variable to this project (⌘N)" : model.selection == .people ? "Add someone's card" : "Add Item (⌘N)")
        .disabled(model.lockedChrome || model.panelOpen)
    }

    private var isProject: Bool { if case .project? = model.selection { true } else { false } }
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
                    case let .failed(message): Text(message).font(.caption).foregroundStyle(Color.attention).fixedSize(horizontal: false, vertical: true)
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
        // Not glass: the sidebar it sits in already is.
        .card(cornerRadius: 14)
    }
}

/// The Projects heading, which also takes a dropped folder or .env file to make a new project, whatever's
/// in the list already. It says so while something is held over it.
struct ProjectsHeader: View {
    @Environment(AppModel.self) private var model
    @State private var targeted = false

    var body: some View {
        HStack {
            Text(targeted ? "Drop to make a new project" : "Projects")
                .foregroundStyle(targeted ? Color.accentColor : .secondary)
            Spacer()
        }
        .contentShape(.rect)
        .animation(.smooth(duration: 0.15), value: targeted)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            Task { model.open(await AppModel.urls(from: providers), on: .projects) }
            return true
        }
        .help("Drop a project folder or .env file here to make a new project")
    }
}

/// The sidebar's welcome for projects: what a project is, with a drop zone that makes one.
struct ProjectsEmptyCard: View {
    @Environment(AppModel.self) private var model
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // A small preview of what a project holds: its .env, with values hidden.
            EnvPreview()
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
            Task { model.open(await AppModel.urls(from: providers), on: .projects) }
            return true
        }
    }
}
