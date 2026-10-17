import SlinkyCoreShared
import SwiftUI
import UniformTypeIdentifiers

/// Layout A: the project as its .env file. Only the values are masked.
struct ProjectView: View {
    @Environment(AppModel.self) private var model
    let projectID: UUID
    @State private var env: AppEnvironment = .local
    @State private var selectedVariable: UUID?
    @State private var selectedMissing: String?
    @State private var showInspector = true
    @State private var dropTargeted = false

    private var project: Project? { model.document.projects.first { $0.id == projectID } }

    var body: some View {
        if let project {
            VStack(spacing: 0) {
                if !project.missing.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("**.env.example** lists \(project.missing.count) variable\(project.missing.count == 1 ? "" : "s") that \(project.missing.count == 1 ? "isn't" : "aren't") saved in Slinky yet.")
                        Spacer()
                    }
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 11))
                    .padding([.horizontal, .top], 14)
                }
                // Values stay on opaque paper: the .env is a sheet floating on the glass.
                envFile(project)
                    .background(Color.paper, in: .rect(cornerRadius: 16))
                    .clipShape(.rect(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                    .padding(14)
            }
            .navigationTitle(project.name)
            .navigationSubtitle(subtitle(project))
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Environment", selection: $env) {
                        ForEach(AppEnvironment.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }
                ToolbarItem {
                    Menu {
                        Button("Import .env File…") { pickEnvFile(project) }
                        Button("Link Folder…") { pickFolder(project) }
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
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .help("Copy this environment as .env lines, or save a .env.example with names only")
                }
                ToolbarItem {
                    Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.right") }
                }
            }
            .inspector(isPresented: $showInspector) {
                inspector(project)
                    .inspectorColumnWidth(min: 260, ideal: 290, max: 360)
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
        var parts = ["\(p.variables.count) variables", "\(secrets) secret"]
        if let folder = p.folders.first { parts.append((folder as NSString).abbreviatingWithTildeInPath) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func envFile(_ p: Project) -> some View {
        if p.variables.isEmpty && p.missing.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "doc.text").font(.system(size: 34)).foregroundStyle(.tertiary)
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
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                    ForEach(Array(p.variables.enumerated()), id: \.element.id) { index, variable in
                        row(number: index + 1, variable: variable)
                    }
                    ForEach(Array(p.missing.enumerated()), id: \.element) { index, name in
                        missingRow(number: p.variables.count + index + 1, name: name)
                    }
                }
                .padding(.vertical, 10)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("").frame(width: 40)
            Text("KEY").frame(width: 260, alignment: .leading)
            HStack(spacing: 0) {
                ForEach(AppEnvironment.allCases) { e in
                    Text(e == .preview ? "PREV" : e == .production ? "PROD" : "LOCAL")
                        .foregroundStyle(e == env ? Color.accentColor : Color.secondary.opacity(0.6))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: 130)
            Text("VALUE").padding(.leading, 12)
            Spacer()
        }
        .font(.system(size: 10, weight: .bold))
        .tracking(0.5)
        .foregroundStyle(.tertiary)
        .padding(.bottom, 4)
    }

    private func row(number: Int, variable: Variable) -> some View {
        let selected = selectedVariable == variable.id
        let value = variable.value(in: env)
        let detection = value.flatMap { Detector.detect($0) }
        return HStack(spacing: 0) {
            Text("\(number)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing).padding(.trailing, 0)
            Text(variable.name)
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .lineLimit(1).truncationMode(.tail)
                .padding(.leading, 14)
                .frame(width: 260, alignment: .leading)
            HStack(spacing: 0) {
                ForEach(AppEnvironment.allCases) { e in
                    Circle()
                        .fill(variable.value(in: e) == nil ? Color.clear : Color.accentColor.opacity(e == env ? 1 : 0.35))
                        .overlay(Circle().strokeBorder(variable.value(in: e) == nil ? Color.secondary.opacity(0.5) : .clear, lineWidth: 1.2))
                        .frame(width: 9, height: 9)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: 130)
            HStack(spacing: 8) {
                if let value {
                    Text(variable.isPlain ? value : Peek.of(value))
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    if variable.isPlain { Chip(text: "public", style: .plain) }
                    if detection?.isLive == true { Chip(text: "live", style: .live) }
                } else {
                    Text("not in \(env.title)").font(.callout).foregroundStyle(.orange)
                }
            }
            .padding(.leading, 12)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 30)
        .padding(.trailing, 12)
        .background(selected ? Color.accentColor.opacity(0.14) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selectedVariable = variable.id; selectedMissing = nil; showInspector = true }
        .contextMenu {
            if let value { Button("Copy Value") { model.copy(value, label: variable.name) } }
            if let value { Button("Copy as KEY=value") { model.copy("\(variable.name)=\(value)", label: "\(variable.name)=…") } }
            Divider()
            Button("Delete", role: .destructive) { model.deleteVariable(variable.id, in: projectID) }
        }
    }

    private func missingRow(number: Int, name: String) -> some View {
        HStack(spacing: 0) {
            Text("\(number)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
            Text(name).font(.system(size: 12.5, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                .padding(.leading, 14).frame(width: 260, alignment: .leading)
            HStack(spacing: 0) {
                ForEach(AppEnvironment.allCases) { _ in
                    Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1.2).frame(width: 9, height: 9).frame(maxWidth: .infinity)
                }
            }
            .frame(width: 130)
            HStack(spacing: 8) {
                Text("missing").foregroundStyle(.orange)
                Button("Add") { tuckMissing(name) }
                    .glassButton().controlSize(.small)
            }
            .padding(.leading, 12)
            Spacer()
        }
        .frame(minHeight: 30)
        .background(selectedMissing == name ? Color.accentColor.opacity(0.14) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selectedMissing = name; selectedVariable = nil; showInspector = true }
    }

    @ViewBuilder
    private func inspector(_ p: Project) -> some View {
        if let id = selectedVariable, let v = p.variables.first(where: { $0.id == id }) {
            VariableInspector(projectID: projectID, variable: v, env: env)
        } else if let name = selectedMissing {
            VStack(alignment: .leading, spacing: 12) {
                Text(name).font(.system(.headline, design: .monospaced))
                Text("Listed in .env.example but not saved in Slinky.").foregroundStyle(.secondary)
                Button("Add Value…") { tuckMissing(name) }.glassProminentButton()
                Spacer()
            }
            .padding(18)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "cursorarrow.click").font(.title).foregroundStyle(.tertiary)
                Text("Select a variable to see its details.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func tuckMissing(_ name: String) {
        model.openAddItem(prefill: "\(name)=", project: projectID)
    }

    /// KEY=value lines for one environment, on the clipboard the careful way (private, clears itself).
    /// For pasting into a host's dashboard. Slinky doesn't write values into files.
    private func copyAsEnv(_ p: Project) {
        let lines = p.variables.compactMap { v in v.value(in: env).map { (v.name, $0) } }
        model.copy(DotEnv.render(lines), label: "\(lines.count) \(env.title) variables from \(p.name)", remember: false)
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
            model.show("Saved \(url.lastPathComponent) with \(names.count) names and no values.")
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

struct VariableInspector: View {
    @Environment(AppModel.self) private var model
    let projectID: UUID
    let variable: Variable
    let env: AppEnvironment
    @State private var editing = false
    @State private var draft = ""

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
                        Button { draft = ""; editing = true } label: { Image(systemName: "pencil") }.help("Replace the \(env.title) value")
                    }
                    .glassButton()
                    .controlSize(.small)
                } else {
                    Text("Not set for \(env.title).").foregroundStyle(.orange)
                    Button("Set \(env.title) Value…") { draft = ""; editing = true }.glassButton()
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
        .sheet(isPresented: $editing) {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(variable.name) · \(env.title)").font(.system(.headline, design: .monospaced))
                SecureField("Paste the new value", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                HStack {
                    if variable.value(in: env) != nil {
                        Button("Remove from \(env.title)", role: .destructive) {
                            model.setValue(nil, variable: variable.id, in: projectID, env: env)
                            editing = false
                        }
                    }
                    Spacer()
                    Button("Cancel") { editing = false }
                    Button("Save") {
                        model.setValue(draft, variable: variable.id, in: projectID, env: env)
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

    private var policyNote: String {
        switch variable.agentPolicy {
        case .agentsCanUse: "AI agents can use this value with your approval. They never see it."
        case .askEveryTime: "AI agents must ask, and you confirm with Touch ID each time."
        case .neverLeaves: "Never shared with AI agents."
        }
    }
}
