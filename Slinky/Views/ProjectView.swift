import SlinkyCoreShared
import SwiftUI
import UniformTypeIdentifiers

/// Layout A: a project's .env, as a list like the library's. Pick an environment at the top (each shows how many
/// variables it has), then Missing (listed in .env.example, not saved yet), Secrets and Public settings. Selecting
/// a variable shows it in the details on the right, with every environment's value in one place.
struct ProjectView: View {
    @Environment(AppModel.self) private var model
    let projectID: UUID
    @State private var env: AppEnvironment = .local
    @State private var selection: ProjectRow?
    // Only whether the pane is open, like the library's. Nothing about any variable.
    @AppStorage("projectInspector") private var showInspector = true
    @State private var dropTargeted = false
    @State private var pushing = false

    /// A row in the list: a saved variable, or a name .env.example expects.
    enum ProjectRow: Hashable { case variable(UUID), missing(String) }

    private var project: Project? { model.document.projects.first { $0.id == projectID } }

    var body: some View {
        if let project {
            VStack(spacing: 0) {
                if project.variables.isEmpty && project.missing.isEmpty {
                    emptyProject(project)
                } else {
                    // In a bar the rows scroll under (with the toolbar's soft edge on Tahoe), not stacked above them.
                    list(project)
                        .topBar {
                            EnvironmentBar(project: project, env: $env)
                                .padding(.horizontal, 16)
                                .padding(.top, 6)
                                .padding(.bottom, 6)
                        }
                }
            }
            .screenTitle(project.name, subtitle: subtitle(project))
            .onAppear(perform: revealIfAsked)
            .onChange(of: model.revealVariable?.id) { revealIfAsked() }
            .toolbar {
                // Import, Share and + share one capsule (like Passwords' sort and +); the details toggle has its own.
                // Import and Share step away while Slinky locks or unlocks, when the toolbar is the locked window's.
                ToolbarItemGroup(placement: .primaryAction) {
                    if !model.lockedChrome {
                        Menu {
                            if !project.folders.isEmpty {
                                Button("Update from Folder…") { model.updateFromFolder(projectID) }
                            }
                            Button("Import .env File…") { pickEnvFile(project) }
                            Button(project.folders.isEmpty ? "Link Folder…" : "Link Another Folder…") { model.chooseFolder(for: projectID) }
                            if !project.folders.isEmpty {
                                Button("Stop Commits with Secrets") {
                                    for folder in project.folders {
                                        model.show((try? Integrations.installGuard(in: folder)) ?? "Couldn't add the commit check.", style: .info)
                                    }
                                }
                            }
                            Divider()
                            Button("Edit Project…") { model.editing = .project(project.id) }
                        } label: {
                            Label("Import", systemImage: "square.and.arrow.down")
                        }
                        .help("Import a .env file or link the project folder")
                        Menu {
                            Button("Copy \(env.title) as .env") { copyAsEnv(project) }
                                .disabled(!project.variables.contains { $0.value(in: env) != nil })
                            Button("Save .env.example…") { saveExample(project) }
                                .disabled(project.variables.isEmpty)
                            Divider()
                            Button("Send to Host…") { pushing = true }
                                .disabled(project.variables.isEmpty)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .help("Copy this environment as .env lines, or save a .env.example with names only")
                    }
                    AddItemButton()
                }
                if !model.lockedChrome {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showInspector.toggle() } label: { Label("Details", systemImage: "sidebar.right") }
                            .help(showInspector ? "Hide Details" : "Show Details")
                    }
                }
            }
            .sheet(isPresented: $pushing) { HostPushSheet(projectID: projectID) }
            .detailsPane(isPresented: $showInspector) {
                inspector(project)
            }
            // A folder or .env file dropped here opens the review of what it would change; a .env whose name doesn't
            // say its environment goes to the tab that's showing.
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                Task { model.open(await AppModel.urls(from: providers), on: .project(projectID, environment: env)) }
                return true
            }
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
        } else {
            ContentUnavailableView("Project not found", systemImage: "folder")
        }
    }

    private func subtitle(_ p: Project) -> String {
        let secrets = p.variables.filter { !$0.isPlain }.count
        // Short: a long subtitle widens the content column and squeezes the sidebar. The folder is in the bar.
        var parts = [counted(p.variables.count, "variable"), counted(secrets, "secret")]
        if !p.missing.isEmpty { parts.append("\(p.missing.count) missing") }
        return parts.joined(separator: " · ")
    }

    private func emptyProject(_ p: Project) -> some View {
        VStack(spacing: 12) {
            // What a project holds, its example values turning into dots, the way a pasted value does.
            EnvPreview(masks: true, fontSize: 12)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.paper.opacity(0.6), in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.14), lineWidth: 1))
                .padding(.bottom, 4)
            Text("Import a .env file").font(.title3.weight(.semibold))
            Text("Drop a .env file here, or choose one. Slinky stores each variable encrypted and separates secrets from public settings.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            HStack {
                Button("Import .env File…") { pickEnvFile(p) }
                Button("Add Variable…") { model.openAddItem(project: projectID) }
            }
            .glassButton()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: List

    private func list(_ p: Project) -> some View {
        let secrets = p.variables.filter { !$0.isPlain }
        let plain = p.variables.filter(\.isPlain)
        return List(selection: $selection) {
            if !p.missing.isEmpty {
                Section {
                    groupTitle("Missing", note: "Listed in .env.example, not saved in Slinky yet")
                    ForEach(p.missing, id: \.self) { name in
                        MissingRow(name: name) { tuckMissing(name) }.tag(ProjectRow.missing(name))
                    }
                }
            }
            if !secrets.isEmpty {
                Section {
                    groupTitle("Secrets")
                    ForEach(secrets) { VariableRow(variable: $0, env: env).tag(ProjectRow.variable($0.id)) }
                }
            }
            if !plain.isEmpty {
                Section {
                    groupTitle("Public settings", note: "Not secret: these ship to the browser anyway")
                    ForEach(plain) { VariableRow(variable: $0, env: env).tag(ProjectRow.variable($0.id)) }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: ProjectRow.self) { rows in
            if rows.count == 1, case let .variable(id)? = rows.first, let v = p.variables.first(where: { $0.id == id }) {
                if let value = v.value(in: env) {
                    Button("Copy \(env.title) Value") { model.copy(value, label: v.name) }
                    Button("Copy as KEY=value") { model.copy("\(v.name)=\(value)", label: "\(v.name)=…") }
                    Divider()
                }
                Button("Delete", role: .destructive) { model.deleteVariable(id, in: projectID) }
            } else if rows.count == 1, case let .missing(name)? = rows.first {
                Button("Add Value…") { tuckMissing(name) }
            }
        } primaryAction: { rows in
            if rows.count == 1, case let .missing(name)? = rows.first { tuckMissing(name) } else { showInspector = true }
        }
        .onChange(of: selection) { _, row in if row != nil, !showInspector { showInspector = true } }
        // ⌘C copies the selected variable's value for this environment; Delete moves it to Recently Deleted.
        .onCommand(#selector(NSText.copy(_:))) {
            if case let .variable(id)? = selection, let v = p.variables.first(where: { $0.id == id }), let value = v.value(in: env) {
                model.copy(value, label: v.name)
            }
        }
        .onDeleteCommand {
            if case let .variable(id)? = selection { model.deleteVariable(id, in: projectID) }
        }
        .focusedSceneValue(\.selectionActions, variableActions(p))
    }

    /// Search or Activity asked for one variable: show its environment and select it.
    private func revealIfAsked() {
        guard let reveal = model.revealVariable else { return }
        model.revealVariable = nil
        env = reveal.env
        if let id = reveal.id, project?.variables.contains(where: { $0.id == id }) == true {
            selection = .variable(id)
            showInspector = true
        }
    }

    /// Edit menu shortcuts for the selected variable, in the environment that's showing.
    private func variableActions(_ p: Project) -> SelectionActions? {
        guard case let .variable(id)? = selection, let v = p.variables.first(where: { $0.id == id }) else { return nil }
        var actions = SelectionActions(edit: { showInspector = true })
        actions.copyName = { model.copyName(v.name) }
        if let value = v.value(in: env) {
            actions.copyLine = { model.copy("\(v.name)=\(value)", label: "\(v.name)=…") }
            actions.copyExport = { model.copy(Broker.shellExports([v.name: value]), label: "export \(v.name)") }
        }
        return actions
    }

    /// A group's title inside the list: not selectable, no line under it (like the library's).
    private func groupTitle(_ text: String, note: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text).font(.headline).foregroundStyle(.secondary)
            if let note { Text(note).font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
        }
        .padding(.top, 6)
        .selectionDisabled()
        .listRowSeparator(.hidden)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Details

    @ViewBuilder
    private func inspector(_ p: Project) -> some View {
        switch selection {
        case let .variable(id)?:
            if let v = p.variables.first(where: { $0.id == id }) {
                VariableInspector(projectID: projectID, variable: v, env: env)
            } else {
                nothingSelected
            }
        case let .missing(name)?:
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "questionmark.square.dashed")
                        .font(.system(size: 22)).foregroundStyle(Color.attention)
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.system(size: 13, weight: .semibold, design: .monospaced)).lineLimit(2).truncationMode(.middle)
                        Text("Missing").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Listed in this project's .env.example, but not saved in Slinky yet. Add its value and Slinky keeps it with the rest.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Add Value…") { tuckMissing(name) }.glassProminentButton()
                Spacer()
            }
            .padding(18)
        case nil:
            nothingSelected
        }
    }

    private var nothingSelected: some View {
        NothingSelected(title: "No Variable Selected", message: "Select a variable to see its value in each environment.")
    }

    private func tuckMissing(_ name: String) {
        model.openAddItem(prefill: "\(name)=", project: projectID)
    }

    /// KEY=value lines for one environment, on the clipboard the careful way (private, clears itself).
    /// For pasting into a host's dashboard. Slinky doesn't write values into files.
    private func copyAsEnv(_ p: Project) {
        let lines = p.variables.compactMap { v in v.value(in: env).map { (v.name, $0) } }
        model.copy(DotEnv.render(lines), label: "\(counted(lines.count, "\(env.title) variable")) from \(p.name)", remember: false)
    }

    /// Names only, empty values: safe to commit, and it tells the next person (or agent) what the project needs.
    private func saveExample(_ p: Project) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ".env.example"
        panel.showsHiddenFiles = true
        panel.message = "A .env.example lists the variable names with no values. It's safe to commit."
        if let folder = p.folders.first { panel.directoryURL = URL(fileURLWithPath: folder) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let names = p.variables.map(\.name)
        let text = "# Variables this project needs. Values live in Slinky, not here.\n" + names.map { "\($0)=" }.joined(separator: "\n") + "\n"
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            model.show("Saved \(url.lastPathComponent) with \(counted(names.count, "name")) and no values.")
        } catch {
            model.show("Couldn't save \(url.lastPathComponent).", style: .info)
        }
    }

    private func pickEnvFile(_ p: Project) {
        let panel = NSOpenPanel()
        panel.showsHiddenFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = "Choose a .env file. Slinky shows what it would change before saving. A .env.example only marks which variables are missing."
        if let folder = p.folders.first { panel.directoryURL = URL(fileURLWithPath: folder) }
        if panel.runModal() == .OK, let url = panel.url { model.open([url], on: .project(projectID, environment: env)) }
    }
}

/// The environment picker for a project, at the top of its list: each environment with how many variables it has,
/// and a small amber dot when some aren't set there. The selection slides between them. The linked folder sits on
/// the right (click to show it in Finder).
struct EnvironmentBar: View {
    @Environment(AppModel.self) private var model
    let project: Project
    @Binding var env: AppEnvironment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill

    var body: some View {
        // Narrow windows lose the folder first, then the counts; the tabs themselves never wrap.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                tabs(counts: true)
                Spacer(minLength: 8)
                folder
            }
            HStack { tabs(counts: true); Spacer(minLength: 0) }
            HStack { tabs(counts: false); Spacer(minLength: 0) }
        }
        .font(.callout)
    }

    private func tabs(counts: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(AppEnvironment.allCases) { e in tab(e, count: counts) }
        }
        .padding(3)
        // Chrome, so glass (a frosted capsule on Sequoia), like the toolbar's own controls.
        .glass(in: .capsule)
        .fixedSize()
    }

    private func tab(_ e: AppEnvironment, count showCount: Bool) -> some View {
        let count = project.variables.filter { $0.value(in: e) != nil }.count
        let short = count < project.variables.count
        let on = e == env
        return Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) { env = e }
        } label: {
            HStack(spacing: 6) {
                Text(e.title).fontWeight(on ? .semibold : .regular)
                if showCount { Text("\(count)").monospacedDigit().foregroundStyle(.secondary) }
                if short { Circle().fill(Color.attention).frame(width: 5, height: 5) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background {
                if on {
                    Capsule()
                        .fill(Color.primary.opacity(0.1))
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(short ? "\(count) of \(counted(project.variables.count, "variable")) set for \(e.title)" : "Every variable is set for \(e.title)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder
    private var folder: some View {
        if let first = project.folders.first {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting(project.folders.map { URL(fileURLWithPath: $0) })
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                    Text((first as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1).truncationMode(.head)
                    if project.folders.count > 1 { Text("+\(project.folders.count - 1)").foregroundStyle(.tertiary) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 300, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
        } else {
            Button {
                model.chooseFolder(for: project.id)
            } label: {
                Label("Link Folder…", systemImage: "folder.badge.plus").font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Link the project folder, so Slinky can check it for keys left in files")
        }
    }
}

/// One variable, like a library row: its icon and name, where it's from or that it isn't set for this environment,
/// its peek, and three small dots for which environments have it.
struct VariableRow: View {
    @Environment(AppModel.self) private var model
    let variable: Variable
    let env: AppEnvironment

    var body: some View {
        let value = variable.value(in: env)
        let live = value.flatMap { Detector.detect($0) }?.isLive == true
        // A service's own icon when Slinky knows it (or one was chosen); otherwise a quiet tile, so a project of
        // forty variables isn't forty colored initials.
        let known = variable.icon != nil || IconResolver.shared.service(for: variable.iconSubject) != nil
        ItemRowLayout(icon: variable.iconSubject, title: variable.name, mono: true,
                      subtitle: subtitle(value), peek: value.map(peek),
                      plainSymbol: known ? nil : (variable.isPlain ? "textformat" : "key.fill")) {
            if live { Chip(text: "live", style: .live) }
            EnvDots(variable: variable, current: env)
        } action: {
            CopyButton { if let value { model.copy(value, label: variable.name) } }
                .disabled(value == nil)
                .help(value == nil ? "Not set for \(env.title)" : "Copy the \(env.title) value")
        }
    }

    private func subtitle(_ value: String?) -> String {
        if value == nil { return "Not set for \(env.title)" }
        if let service = IconResolver.shared.service(for: variable.iconSubject)?.name { return service }
        return variable.provider ?? (variable.isPlain ? "Public setting" : "Secret")
    }

    /// Public settings show their value (short); secrets only their peek.
    private func peek(_ value: String) -> String {
        guard variable.isPlain else { return Peek.of(value) }
        return value.count > 26 ? String(value.prefix(24)) + "…" : value
    }
}

/// Which environments a variable is set in: Local, Preview, Production, left to right. The one you're looking at
/// is the strongest; an empty ring means not set there.
struct EnvDots: View {
    let variable: Variable
    let current: AppEnvironment
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        let onHighlight = prominence == .increased
        HStack(spacing: 3) {
            ForEach(AppEnvironment.allCases) { e in
                let set = variable.value(in: e) != nil
                let tint: Color = onHighlight ? .white : .accentColor
                Circle()
                    .fill(set ? tint.opacity(e == current ? 1 : 0.4) : .clear)
                    .overlay(Circle().strokeBorder(set ? .clear : (onHighlight ? Color.white.opacity(0.6) : Color.secondary.opacity(0.5)), lineWidth: 1))
                    .frame(width: 6, height: 6)
            }
        }
        .help(help)
        .accessibilityLabel(help)
    }

    private var help: String {
        let set = AppEnvironment.allCases.filter { variable.value(in: $0) != nil }.map(\.title)
        if set.count == AppEnvironment.allCases.count { return "Set for every environment" }
        if set.isEmpty { return "Not set anywhere" }
        return "Set for " + set.formatted(.list(type: .and))
    }
}

/// A name the project's .env.example expects that Slinky doesn't have yet.
struct MissingRow: View {
    let name: String
    let add: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.attention.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.5]))
                .frame(width: 32, height: 32)
                .overlay(Image(systemName: "plus").font(.callout.weight(.semibold)).foregroundStyle(Color.attention))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Text("Not saved in Slinky yet").font(.subheadline).foregroundStyle(.tertiary)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            Button("Add…", action: add)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .fixedSize()
        }
        .padding(.vertical, 6)
    }
}

struct VariableInspector: View {
    @Environment(AppModel.self) private var model
    let projectID: UUID
    let variable: Variable
    let env: AppEnvironment
    @State private var editing = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var renameProblem: String?
    /// Which environment's value the sheet sets (any of them, from the Environments list).
    @State private var editEnv: AppEnvironment = .local
    @State private var draft = ""
    @State private var note = ""
    @State private var link = ""

    var body: some View {
        let value = variable.value(in: env)
        // The same shape as an item's details: a header, then a grouped form.
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ServiceIcon(subject: variable.iconSubject, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(variable.name)
                        .font(.title3.monospaced().weight(.semibold))
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Text([variable.isPlain ? "Public setting" : "Secret", variable.provider, env.title].compactMap { $0 }.joined(separator: " · "))
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                moreMenu
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Form {
                Section {
                    if let value {
                        if variable.isPlain {
                            Text(value).font(.callout.monospaced()).textSelection(.enabled)
                                .lineLimit(3).truncationMode(.middle)
                        } else {
                            RevealField(value: value)
                        }
                        HStack(spacing: 8) {
                            CopyButton { model.copy(value, label: variable.name) }
                                .glassProminentButton()
                            Menu {
                                Button("Copy as \(variable.name)=…") { model.copy("\(variable.name)=\(value)", label: "\(variable.name)=…") }
                                Button("Replace \(env.title) Value…") { edit(env) }
                            } label: {
                                Image(systemName: "ellipsis")
                            }
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .glassButton()
                            .accessibilityLabel("More")
                        }
                    } else {
                        Text("Not set for \(env.title).").foregroundStyle(Color.attention)
                        Button("Set \(env.title) Value…") { edit(env) }.glassProminentButton()
                    }
                }

                // Every environment at a glance, each with its own Set or Replace.
                Section("Environments") {
                    ForEach(AppEnvironment.allCases) { e in
                        let v = variable.value(in: e)
                        // One line each: the pane is narrow, and a labeled row put the value under its name.
                        HStack(spacing: 8) {
                            Text(e.title).fontWeight(e == env ? .semibold : .regular)
                                .frame(width: 78, alignment: .leading)
                                Group {
                                    if let v {
                                        Text(variable.isPlain ? v : Peek.of(v)).foregroundStyle(.secondary)
                                    } else {
                                        Text("Not set").foregroundStyle(Color.attention)
                                    }
                                }
                                .font(.callout.monospaced())
                                .lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 4)
                                Button(v == nil ? "Set…" : "Replace…") { edit(e) }
                                    .buttonStyle(.borderless).fixedSize()
                                    .accessibilityLabel(v == nil ? "Set \(e.title) value" : "Replace \(e.title) value")
                        }
                    }
                }

                if !variable.isPlain {
                    Section {
                        Picker("AI agents", selection: Binding(
                            get: { variable.agentPolicy },
                            set: { model.setPolicy($0, variable: variable.id, in: projectID) })) {
                            ForEach(AgentPolicy.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    } footer: {
                        Text(policyNote).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Note and link") {
                    TextField("Note", text: $note, prompt: Text("Optional, like where to make a new one"), axis: .vertical)
                        .labelsHidden()
                        .lineLimit(1...4)
                        .onSubmit(saveDetails)
                    HStack(spacing: 6) {
                        TextField("Link", text: $link, prompt: Text("Optional, like the dashboard page"))
                            .labelsHidden()
                            .onSubmit(saveDetails)
                        if let url = ItemActions.url(variable.link) {
                            Button("Open") { NSWorkspace.shared.open(url) }.buttonStyle(.borderless).help(url.absoluteString)
                        }
                    }
                    if !link.trimmingCharacters(in: .whitespaces).isEmpty, Links.normalized(link) == nil {
                        Text("Only web addresses (https) are kept.").font(.caption).foregroundStyle(Color.attention)
                    }
                }

                UsageSection(names: [variable.name], id: variable.id)

                Section {
                    LabeledContent("Updated", value: variable.updated.formatted(.relative(presentation: .named)))
                    LabeledContent("Added", value: variable.created.formatted(date: .abbreviated, time: .omitted))
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack {
                Button("Delete", role: .destructive) { model.deleteVariable(variable.id, in: projectID) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.danger)
                    .help("Move to Recently Deleted")
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .onAppear(perform: loadDetails)
        .onChange(of: variable.id) { old, _ in
            // Switching rows saves what was typed for the previous variable first.
            model.setVariableDetails(note: note, link: link, variable: old, in: projectID)
            loadDetails()
        }
        .onDisappear(perform: saveDetails)
        .sheet(isPresented: $editing) {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(variable.name) · \(editEnv.title)").font(.system(.headline, design: .monospaced))
                SecureField("New value", text: $draft, prompt: Text("Paste the new value"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                // Often an environment uses the same value as Local: one click, no pasting.
                if editEnv != .local, let local = variable.value(in: .local), local != variable.value(in: editEnv) {
                    Button("Use the Local Value (\(Peek.of(local)))") {
                        model.setValue(local, variable: variable.id, in: projectID, env: editEnv)
                        editing = false
                    }
                    .buttonStyle(.link)
                }
                HStack {
                    if variable.value(in: editEnv) != nil {
                        Button("Remove from \(editEnv.title)", role: .destructive) {
                            model.setValue(nil, variable: variable.id, in: projectID, env: editEnv)
                            editing = false
                        }
                    }
                    Spacer()
                    Button("Cancel") { editing = false }
                        .keyboardShortcut(.cancelAction)
                        .glassButton()
                    Button("Save") {
                        model.setValue(draft, variable: variable.id, in: projectID, env: editEnv)
                        editing = false
                    }
                    .glassProminentButton()
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.isEmpty)
                }
                .dialogButtons()
            }
            .padding(22)
            .frame(width: 440)
        }
    }

    /// Rename, Secret or Public, and copy or move to another project.
    private var moreMenu: some View {
        Menu {
            Button("Rename…") { newName = variable.name; renameProblem = nil; renaming = true }
            Button(variable.isPlain ? "Make It a Secret" : "Make It a Public Setting") {
                model.setPlain(!variable.isPlain, variable: variable.id, in: projectID)
            }
            let others = model.document.projects.filter { $0.id != projectID }
            if !others.isEmpty {
                Divider()
                Menu("Copy to Project") {
                    ForEach(others) { p in Button(p.name) { model.copyVariable(variable.id, from: projectID, to: p.id, move: false) } }
                }
                Menu("Move to Project") {
                    ForEach(others) { p in Button(p.name) { model.copyVariable(variable.id, from: projectID, to: p.id, move: true) } }
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .glassButton()
        .buttonBorderShape(.circle)
        .help("Rename, make it public or secret, or copy it to another project")
        .popover(isPresented: $renaming, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Rename \(variable.name)").font(.headline)
                TextField("Name", text: $newName, prompt: Text("RESEND_API_KEY"))
                    .labelsHidden()
                    .font(.body.monospaced())
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(rename)
                if let renameProblem {
                    Text(renameProblem).font(.callout).foregroundStyle(Color.danger).fixedSize(horizontal: false, vertical: true)
                }
                Text("Your project's code reads it by this name, so change it there too.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Cancel") { renaming = false }.keyboardShortcut(.cancelAction).glassButton()
                    Button("Rename", action: rename).keyboardShortcut(.defaultAction).glassProminentButton()
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .dialogButtons()
            }
            .padding(16)
            .frame(width: 340)
        }
    }

    private func rename() {
        renameProblem = model.renameVariable(variable.id, in: projectID, to: newName)
        if renameProblem == nil { renaming = false }
    }

    private func edit(_ e: AppEnvironment) {
        editEnv = e
        draft = ""
        editing = true
    }

    private func loadDetails() {
        note = variable.note ?? ""
        link = variable.link ?? ""
    }

    private func saveDetails() {
        guard model.isUnlocked else { return }
        model.setVariableDetails(note: note, link: link, variable: variable.id, in: projectID)
        link = Links.normalized(link) ?? (link.isEmpty ? "" : link)
    }

    private var policyNote: String {
        switch variable.agentPolicy {
        case .agentsCanUse: "AI agents can use this value with your approval. They never see it."
        case .askEveryTime: "AI agents must ask, and you confirm with Touch ID each time."
        case .neverLeaves: "Never shared with AI agents."
        }
    }
}
