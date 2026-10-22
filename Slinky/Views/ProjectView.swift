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
    @State private var showInspector = true
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
                    EnvironmentBar(project: project, env: $env)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                    list(project)
                }
            }
            .screenTitle(project.name, subtitle: subtitle(project))
            .toolbar {
                // Away while Slinky locks or unlocks, when the toolbar is the locked window's.
                if !model.lockedChrome {
                    ToolbarItem {
                        Menu {
                            Button("Import .env File…") { pickEnvFile(project) }
                            Button("Link Folder…") { pickFolder(project) }
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
                            Label("Add", systemImage: "square.and.arrow.down")
                        }
                        .help("Import a .env file or link the project folder")
                    }
                    ToolbarItem {
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
                    ToolbarItem {
                        Button { showInspector.toggle() } label: { Label("Details", systemImage: "sidebar.right") }
                            .help(showInspector ? "Hide Details" : "Show Details")
                    }
                }
            }
            .sheet(isPresented: $pushing) { HostPushSheet(projectID: projectID) }
            .detailsPane(isPresented: $showInspector) {
                inspector(project)
            }
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in
                            var isDir: ObjCBool = false
                            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                                model.linkFolder(url, to: projectID)
                            } else {
                                model.importEnvFile(url, into: projectID, env: env)
                            }
                        }
                    }
                }
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
        VStack(spacing: 8) {
            Image(systemName: "cursorarrow.click").font(.title).foregroundStyle(.tertiary)
            Text("Select a variable to see its details.").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        panel.message = "Choose a .env file to import. Choosing a .env.example only marks which variables are missing."
        if let folder = p.folders.first { panel.directoryURL = URL(fileURLWithPath: folder) }
        if panel.runModal() == .OK, let url = panel.url { model.importEnvFile(url, into: projectID, env: env) }
    }

    private func pickFolder(_ p: Project) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Link"
        if panel.runModal() == .OK, let url = panel.url { model.linkFolder(url, to: projectID) }
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
        .background(Color.secondary.opacity(0.1), in: .capsule)
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
                        .fill(Color.paper)
                        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
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
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.prompt = "Link"
                if panel.runModal() == .OK, let url = panel.url { model.linkFolder(url, to: project.id) }
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
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.attention.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.5]))
                .frame(width: 28, height: 28)
                .overlay(Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.attention))
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Text("Not saved in Slinky yet").font(.caption).foregroundStyle(.tertiary)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            Button("Add…", action: add)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .fixedSize()
        }
        .padding(.vertical, 4)
    }
}

struct VariableInspector: View {
    @Environment(AppModel.self) private var model
    let projectID: UUID
    let variable: Variable
    let env: AppEnvironment
    @State private var editing = false
    /// Which environment's value the sheet sets (any of them, from the Environments list).
    @State private var editEnv: AppEnvironment = .local
    @State private var draft = ""
    @State private var note = ""
    @State private var link = ""

    var body: some View {
        let value = variable.value(in: env)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ServiceIcon(subject: variable.iconSubject, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(variable.name).font(.system(size: 13, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                        Text([variable.provider, env.title].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let value {
                    if variable.isPlain {
                        Text(value).font(.system(size: 12.5, design: .monospaced)).textSelection(.enabled)
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.background.secondary, in: .rect(cornerRadius: 9))
                    } else {
                        RevealField(value: value)
                    }
                    HStack {
                        CopyButton { model.copy(value, label: variable.name) }
                        Button { model.copy("\(variable.name)=\(value)", label: "\(variable.name)=…") } label: { Text("KEY=value") }
                        Button { edit(env) } label: { Image(systemName: "pencil") }.help("Replace the \(env.title) value")
                    }
                    .glassButton()
                    .controlSize(.small)
                } else {
                    Text("Not set for \(env.title).").foregroundStyle(Color.attention)
                    Button("Set \(env.title) Value…") { edit(env) }.glassButton()
                }

                // Every environment at a glance, each with its own Set or Replace.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Environments").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        ForEach(AppEnvironment.allCases) { e in
                            let v = variable.value(in: e)
                            HStack(spacing: 8) {
                                Text(e.title).font(.callout).fontWeight(e == env ? .semibold : .regular)
                                    .frame(width: 78, alignment: .leading)
                                Group {
                                    if let v {
                                        Text(variable.isPlain ? v : Peek.of(v)).foregroundStyle(.secondary)
                                    } else {
                                        Text("Not set").foregroundStyle(Color.attention)
                                    }
                                }
                                .font(.system(size: 11.5, design: .monospaced))
                                .lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 4)
                                Button(v == nil ? "Set…" : "Replace…") { edit(e) }
                                    .buttonStyle(.borderless).controlSize(.small).fixedSize()
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            if e != AppEnvironment.allCases.last { Divider().padding(.leading, 10) }
                        }
                    }
                    .background(Color.paper, in: .rect(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
                }

                if !variable.isPlain {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AI agents").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Picker("Agents", selection: Binding(
                            get: { variable.agentPolicy },
                            set: { model.setPolicy($0, variable: variable.id, in: projectID) })) {
                            ForEach(AgentPolicy.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text(policyNote).font(.caption2).foregroundStyle(.tertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Note and link").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("Note", text: $note, prompt: Text("Optional, like where to make a new one"), axis: .vertical)
                        .lineLimit(1...4)
                        .onSubmit(saveDetails)
                    HStack(spacing: 6) {
                        TextField("Link", text: $link, prompt: Text("Optional, like the dashboard page"))
                            .onSubmit(saveDetails)
                        if let url = ItemActions.url(variable.link) {
                            Button("Open") { NSWorkspace.shared.open(url) }.help(url.absoluteString)
                        }
                    }
                    if !link.trimmingCharacters(in: .whitespaces).isEmpty, Links.normalized(link) == nil {
                        Text("Only web addresses (https) are kept.").font(.caption2).foregroundStyle(Color.attention)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow { Text("Updated").foregroundStyle(.secondary); Text(variable.updated.formatted(.relative(presentation: .named))) }
                    GridRow { Text("Added").foregroundStyle(.secondary); Text(variable.created.formatted(date: .abbreviated, time: .omitted)) }
                }
                .font(.caption)

                Button("Delete Variable", role: .destructive) { model.deleteVariable(variable.id, in: projectID) }
                    .buttonStyle(.borderless)
                    .font(.callout)
            }
            .padding(18)
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
                SecureField("Paste the new value", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                HStack {
                    if variable.value(in: editEnv) != nil {
                        Button("Remove from \(editEnv.title)", role: .destructive) {
                            model.setValue(nil, variable: variable.id, in: projectID, env: editEnv)
                            editing = false
                        }
                    }
                    Spacer()
                    Button("Cancel") { editing = false }
                    Button("Save") {
                        model.setValue(draft, variable: variable.id, in: projectID, env: editEnv)
                        editing = false
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.isEmpty)
                }
            }
            .padding(22)
            .frame(width: 440)
        }
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
