import SlinkyCoreShared
import SwiftUI

/// Edit floats like Add Item and New Project. Values are never shown here in full:
/// the current one appears as a short peek, and "Replace" takes a new one.
struct EditOverlay: View {
    @Environment(AppModel.self) private var model
    let target: EditTarget

    var body: some View {
        ZStack {
            PanelBackdrop(close: close)
            EditPanel(target: target, close: close)
                .id(target)
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { model.editing = nil }
    }
}

private struct EditPanel: View {
    @Environment(AppModel.self) private var model
    let target: EditTarget
    let close: () -> Void

    // Shared drafts. Only the ones the target uses matter.
    @State private var name = ""
    @State private var from = ""
    @State private var note = ""
    @State private var newValue = ""
    @State private var replacing = false
    @State private var hasExpiry = false
    @State private var expiry = Date.now
    @State private var policy: AgentPolicy = .agentsCanUse
    @State private var keptKind: KeptKind = .recoveryKey
    @State private var newCodes = ""
    @State private var resetUsed = false
    @State private var folders: [String] = []
    @State private var loaded = false
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Monogram(text: name, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline)
                    Text(kindLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Keycap("esc")
            }
            .padding(.bottom, 16)

            FieldCard {
                fields
            }

            footer.padding(.top, 18)
        }
        .padding(24)
        .frame(width: 620)
        .glass(in: .rect(cornerRadius: 28))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 14)
        .scaleEffect(appeared ? 1 : 0.95)
        .offset(y: appeared ? 0 : 14)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.88), value: replacing)
        .animation(.spring(response: 0.3, dampingFraction: 0.88), value: hasExpiry)
        .onAppear {
            load()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) { appeared = true }
        }
    }

    // MARK: Fields per kind

    @ViewBuilder
    private var fields: some View {
        switch target {
        case let .key(id):
            if let key = model.document.keys.first(where: { $0.id == id }) {
                FieldRow("Name") { plainField($name, prompt: "GITHUB_TOKEN", mono: true) }
                valueRow(current: key.value)
                FieldRow("Expires") {
                    HStack {
                        if hasExpiry {
                            DatePicker("", selection: $expiry, displayedComponents: .date).labelsHidden()
                        }
                        Spacer()
                        Toggle("", isOn: $hasExpiry).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                }
                FieldRow("AI agents") {
                    Picker("", selection: $policy) {
                        ForEach(AgentPolicy.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                FieldRow("Note", last: true) { plainField($note, prompt: "Optional, like which account it belongs to") }
            }
        case let .kept(id):
            if let item = model.document.kept.first(where: { $0.id == id }) {
                FieldRow("Name") { plainField($name, prompt: "Apple Account recovery key") }
                FieldRow("Type") {
                    Picker("", selection: $keptKind) {
                        Text(KeptKind.recoveryKey.title).tag(KeptKind.recoveryKey)
                        Text(KeptKind.setupKey.title).tag(KeptKind.setupKey)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    Spacer(minLength: 0)
                }
                FieldRow("Website or app") { plainField($from, prompt: "Optional") }
                valueRow(current: item.value)
                FieldRow("Note", last: true) { plainField($note, prompt: "Optional, like where the printed copy is") }
            }
        case let .codes(id):
            if let set = model.document.codeSets.first(where: { $0.id == id }) {
                FieldRow("Account") { plainField($name, prompt: "GitHub") }
                FieldRow("Username") { plainField($from, prompt: "Optional") }
                FieldRow("Codes", last: !replacing) {
                    HStack {
                        Text("\(set.remaining) of \(set.codes.count) left").foregroundStyle(.secondary)
                        Spacer()
                        Button(replacing ? "Keep These Codes" : "Replace with New Codes…") {
                            replacing.toggle()
                            newCodes = ""
                        }
                        .buttonStyle(.borderless)
                    }
                }
                if replacing {
                    FieldRow("New codes", last: true) {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("", text: $newCodes, prompt: Text("Paste the new codes from \(name.isEmpty ? "the website" : name)"), axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, design: .monospaced))
                                .lineLimit(3...6)
                            Text(parsedCodes.count >= 2 ? "\(parsedCodes.count) codes found. They'll replace the old ones." : "When you make new codes, the old ones stop working.")
                                .font(.caption).foregroundStyle(parsedCodes.count >= 2 ? Color.green : Color.secondary)
                        }
                    }
                }
            }
        case .project:
            FieldRow("Name") { plainField($name, prompt: "Slinky") }
            FieldRow("Folders", last: true) {
                VStack(alignment: .leading, spacing: 6) {
                    if folders.isEmpty {
                        Text("No folder linked").foregroundStyle(.secondary)
                    }
                    ForEach(folders, id: \.self) { path in
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill").foregroundStyle(.tint)
                            Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1).truncationMode(.head)
                            Spacer()
                            IconButton(symbol: "xmark", help: "Unlink this folder") { folders.removeAll { $0 == path } }
                        }
                    }
                    Button("Link a Folder…", action: linkFolder).buttonStyle(.borderless)
                }
            }
        }
    }

    private func valueRow(current: String) -> some View {
        FieldRow(replacing ? "New value" : "Value") {
            if replacing {
                HStack {
                    SecureField("", text: $newValue, prompt: Text("Paste the new value"))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                    Button("Keep Current") { replacing = false; newValue = "" }.buttonStyle(.borderless)
                }
            } else {
                HStack {
                    Text(Peek.of(current)).font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Replace…") { replacing = true }.buttonStyle(.borderless)
                }
            }
        }
    }

    private func plainField(_ text: Binding<String>, prompt: String, mono: Bool = false) -> some View {
        TextField("", text: text, prompt: Text(prompt))
            .textFieldStyle(.plain)
            .font(mono ? .system(size: 13, weight: .medium, design: .monospaced) : .body)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            // Undoable (Recently Deleted keeps it 30 days), so no confirmation.
            Button(deleteButton, role: .destructive) { delete() }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            Spacer()
            Button("Cancel", action: close)
                .keyboardShortcut(.cancelAction)
                .glassButton()
                .controlSize(.large)
            Button(action: save) {
                HStack(spacing: 8) {
                    Text("Save Changes")
                    Text("↵").font(.callout.weight(.semibold)).opacity(0.6)
                }
            }
            .keyboardShortcut(.defaultAction)
            .glassProminentButton()
            .controlSize(.large)
            .disabled(!canSave)
        }
    }

    // MARK: Behavior

    private var title: String {
        switch target {
        case .key: "Edit Key or Token"
        case .kept: "Edit Recovery Key"
        case .codes: "Edit Recovery Codes"
        case .project: "Edit Project"
        }
    }

    private var kindLabel: String {
        switch target {
        case let .key(id): return model.document.keys.first { $0.id == id }?.provider ?? "Keys & Tokens"
        case .kept, .codes: return "Recovery"
        case let .project(id):
            let n = model.document.projects.first { $0.id == id }?.variables.count ?? 0
            return "\(n) \(n == 1 ? "variable" : "variables")"
        }
    }

    private var deleteButton: String {
        if case .project = target { return "Delete Project" }
        return "Delete"
    }

    private var parsedCodes: [String] { RecoveryCodes.extract(newCodes) }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if case .codes = target, replacing { return parsedCodes.count >= 2 }
        if replacing { return !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return true
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch target {
        case let .key(id):
            guard let key = model.document.keys.first(where: { $0.id == id }) else { return }
            name = key.name
            note = key.note ?? ""
            hasExpiry = key.expires != nil
            expiry = key.expires ?? Calendar.current.date(byAdding: .day, value: 90, to: .now) ?? .now
            policy = key.agentPolicy
        case let .kept(id):
            guard let item = model.document.kept.first(where: { $0.id == id }) else { return }
            name = item.label
            from = item.from ?? ""
            note = item.note ?? ""
            keptKind = item.kind == .setupKey ? .setupKey : .recoveryKey
        case let .codes(id):
            guard let set = model.document.codeSets.first(where: { $0.id == id }) else { return }
            name = set.account
            from = set.username ?? ""
        case let .project(id):
            guard let p = model.document.projects.first(where: { $0.id == id }) else { return }
            name = p.name
            folders = p.folders
        }
    }

    private func save() {
        guard canSave else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch target {
        case let .key(id):
            guard var key = model.document.keys.first(where: { $0.id == id }) else { return }
            key.name = trimmedName
            key.note = note.isEmpty ? nil : note
            key.expires = hasExpiry ? expiry : nil
            key.agentPolicy = policy
            if replacing, !value.isEmpty {
                key.value = value
                let detection = Detector.detect(value)
                key.provider = detection?.provider ?? key.provider
                key.isLive = detection?.isLive ?? false
            }
            model.update(key)
        case let .kept(id):
            guard var item = model.document.kept.first(where: { $0.id == id }) else { return }
            item.label = trimmedName
            item.from = from.isEmpty ? nil : from
            item.note = note.isEmpty ? nil : note
            item.kind = keptKind
            if replacing, !value.isEmpty {
                item.value = value
                item.printedCopy = false
            }
            model.update(item)
        case let .codes(id):
            guard var set = model.document.codeSets.first(where: { $0.id == id }) else { return }
            set.account = trimmedName
            set.username = from.isEmpty ? nil : from
            if replacing, parsedCodes.count >= 2 {
                set.codes = parsedCodes
                set.used = []
                set.regenerated = .now
            }
            model.update(set)
        case let .project(id):
            guard var p = model.document.projects.first(where: { $0.id == id }) else { return }
            p.name = trimmedName
            p.folders = folders
            // Re-read .env.example from the first linked folder, if there is one.
            if let first = folders.first,
               let example = ProjectScan.scan(URL(fileURLWithPath: first)).exampleFile.map({ URL(fileURLWithPath: first).appendingPathComponent($0) }),
               let text = try? String(contentsOf: example, encoding: .utf8) {
                p.expected = DotEnv.names(text)
            } else if folders.isEmpty {
                p.expected = []
            }
            model.update(p)
        }
        close()
    }

    private func delete() {
        switch target {
        case let .key(id): model.deleteKey(id)
        case let .kept(id): model.deleteKept(id)
        case let .codes(id): model.deleteCodeSet(id)
        case let .project(id): model.deleteProject(id)
        }
        close()
    }

    private func linkFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Link"
        if panel.runModal() == .OK, let url = panel.url, !folders.contains(url.path) {
            folders.append(url.path)
        }
    }
}

// MARK: Field layout

/// Rows of label + control on opaque paper, separated by hairlines.
struct FieldCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color.paper, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1))
    }
}

struct FieldRow<Content: View>: View {
    let label: String
    var last: Bool
    @ViewBuilder var content: Content

    init(_ label: String, last: Bool = false, @ViewBuilder content: () -> Content) {
        self.label = label
        self.last = last
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(label)
                    .foregroundStyle(.secondary)
                    .frame(width: 112, alignment: .leading)
                HStack { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            if !last { Divider().padding(.leading, 16) }
        }
    }
}
