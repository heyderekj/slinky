import SlinkyCoreShared
import SwiftUI

/// Edit floats like Add Item and New Project. Values are never shown here in full:
/// the current one appears as a short peek, and "Replace" takes a new one.
struct EditOverlay: View {
    @Environment(AppModel.self) private var model
    let target: EditTarget
    @State private var closeRequest = 0

    var body: some View {
        ZStack {
            PanelBackdrop(close: { closeRequest += 1 })
            EditPanel(target: target, close: close, closeRequest: closeRequest)
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
    /// Goes up each time the backdrop is clicked: close, or ask first if something changed.
    var closeRequest = 0

    // Shared drafts. Only the ones the target uses matter.
    @State private var name = ""
    @State private var from = ""
    @State private var note = ""
    @State private var link = ""
    @State private var service: String?
    @State private var issuerID = ""
    @State private var keyID = ""
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
    @State private var original: Snapshot?
    @State private var confirmingDiscard = false
    @State private var appeared = false
    /// The fields' natural height, so they scroll only when the window is too short for them.
    @State private var fieldsHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 12)

            // In a short window the fields scroll and the name and Save stay put.
            ScrollView {
                FieldCard {
                    fields
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fieldsHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: fieldsHeight > 0 ? fieldsHeight : nil)

            footer.padding(.top, 14)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 620)
        .glass(in: .rect(cornerRadius: 28))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 14)
        .padding(.vertical, 20)   // room from the window's edges when it's short
        .panelEntrance(appeared)
        .animation(.spring(response: 0.3, dampingFraction: 0.88), value: replacing)
        .animation(.spring(response: 0.3, dampingFraction: 0.88), value: hasExpiry)
        .onChange(of: closeRequest) { requestClose() }
        .onAppear {
            load()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) { appeared = true }
        }
    }

    // MARK: Header

    /// The item itself, not the form's name: its icon (click to choose another), its name as typed,
    /// and what it is. A close button where the "esc" hint was; Esc still works.
    private var header: some View {
        HStack(spacing: 14) {
            Group {
                if let ref = libraryRef {
                    Button { model.choosingIcon = ref } label: { ServiceIcon(subject: iconSubject, size: 44) }
                        .buttonStyle(.plain)
                        .help("Choose Icon…")
                } else {
                    ServiceIcon(subject: iconSubject, size: 44)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(name.trimmingCharacters(in: .whitespaces).isEmpty ? title : name)
                    .font(.system(size: 17, weight: .semibold, design: isKey ? .monospaced : .default))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentTransition(.opacity)
                Text(kindLabel).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            PanelCloseButton(action: requestClose)
        }
    }

    private var isKey: Bool { if case .key = target { true } else { false } }

    private var libraryRef: LibraryRef? {
        switch target {
        case let .key(id): .key(id)
        case let .kept(id): .kept(id)
        case let .codes(id): .codes(id)
        case let .file(id): .file(id)
        case .project: nil
        }
    }

    // MARK: Fields per kind

    @ViewBuilder
    private var fields: some View {
        switch target {
        case let .key(id):
            if let key = model.document.keys.first(where: { $0.id == id }) {
                FieldRow("Name") { plainField($name, prompt: "GITHUB_TOKEN", mono: true, max: FieldLimit.name) }
                valueRow(current: key.value)
                FieldRow("Expires") {
                    HStack {
                        if hasExpiry {
                            DatePicker("Expiry date", selection: $expiry, displayedComponents: .date).labelsHidden()
                        }
                        Spacer()
                        Toggle("Expires", isOn: $hasExpiry).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                }
                FieldRow("AI agents") {
                    Picker("AI agents", selection: $policy) {
                        ForEach(AgentPolicy.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                serviceRow
                FieldRow("Note") { plainField($note, prompt: "Optional, like which account it belongs to") }
                linkRow
            }
        case let .kept(id):
            if let item = model.document.kept.first(where: { $0.id == id }) {
                FieldRow("Name") { plainField($name, prompt: "Apple Account recovery key", max: FieldLimit.name) }
                FieldRow("Type") {
                    Picker("Type", selection: $keptKind) {
                        Text(KeptKind.recoveryKey.title).tag(KeptKind.recoveryKey)
                        Text(KeptKind.setupKey.title).tag(KeptKind.setupKey)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    Spacer(minLength: 0)
                }
                FieldRow("Website or app") { plainField($from, prompt: "Optional", max: FieldLimit.name) }
                valueRow(current: item.value)
                serviceRow
                FieldRow("Note") { plainField($note, prompt: "Optional, like where the printed copy is") }
                linkRow
            }
        case let .codes(id):
            if let set = model.document.codeSets.first(where: { $0.id == id }) {
                FieldRow("Account") { plainField($name, prompt: "GitHub", max: FieldLimit.name) }
                FieldRow("Username") { plainField($from, prompt: "Optional", max: FieldLimit.name) }
                serviceRow
                FieldRow("Note") { plainField($note, prompt: "Optional, like which account they belong to") }
                linkRow(last: false)
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
                            TextField("New codes", text: $newCodes, prompt: Text("Paste the new codes from \(name.isEmpty ? "the website" : name)"), axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, design: .monospaced))
                                .lineLimit(3...6)
                            Text(parsedCodes.count >= 2 ? "\(parsedCodes.count) codes found. They'll replace the old ones." : "When you make new codes, the old ones stop working.")
                                .font(.caption).foregroundStyle(parsedCodes.count >= 2 ? Color.done : Color.secondary)
                        }
                    }
                }
            }
        case let .file(id):
            if let file = model.document.secretFiles.first(where: { $0.id == id }) {
                FieldRow("Name") { plainField($name, prompt: "App Store Connect API key", max: FieldLimit.name) }
                FieldRow("File") { Text(file.filename).foregroundStyle(.secondary); Spacer(minLength: 0) }
                if file.kind == .appStoreConnectKey {
                    FieldRow("Issuer ID") { plainField($issuerID, prompt: "From App Store Connect › Users and Access › Integrations", mono: true) }
                    FieldRow("Key ID") { plainField($keyID, prompt: "ABCD1234EF", mono: true) }
                }
                serviceRow
                FieldRow("Note") { plainField($note, prompt: "Optional, like which app or team it's for") }
                linkRow
            }
        case .project:
            FieldRow("Name") { plainField($name, prompt: "Slinky", max: FieldLimit.name) }
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

    /// Where it lives: the carousel, with search. Picking one with no link yet fills in its key page.
    private var serviceRow: some View {
        FieldRow("Where it lives") {
            ServicePicker(selection: $service, subject: iconSubject) { id in
                guard link.trimmingCharacters(in: .whitespaces).isEmpty, let s = id.flatMap(ServiceCatalog.service(id:)) else { return }
                link = s.tokenURL ?? s.domains.first.map { "https://\($0)" } ?? ""
            }
        }
    }

    private var linkRow: some View { linkRow(last: true) }

    private func linkRow(last: Bool) -> some View {
        FieldRow("Link", last: last) {
            plainField($link, prompt: "Optional, like the page where you manage it", max: FieldLimit.link)
                .onSubmit { link = Links.normalized(link) ?? link }
        }
    }

    private func valueRow(current: String) -> some View {
        FieldRow(replacing ? "New value" : "Value") {
            if replacing {
                HStack {
                    SecureField("New value", text: $newValue, prompt: Text("Paste the new value"))
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

    private func plainField(_ text: Binding<String>, prompt: String, mono: Bool = false, max: Int = FieldLimit.note) -> some View {
        PlainField(text: text, prompt: prompt, mono: mono, max: max)
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        if confirmingDiscard {
            HStack(spacing: 10) {
                Label("Discard your changes?", systemImage: "exclamationmark.circle")
                    .font(.callout.weight(.semibold))
                Spacer()
                Button("Discard", role: .destructive, action: close)
                    .glassButton()
                    .controlSize(.large)
                Button("Keep Editing") { withAnimation(.snappy) { confirmingDiscard = false } }
                    .keyboardShortcut(.defaultAction)
                    .glassProminentButton()
                    .controlSize(.large)
                // Esc again also keeps editing.
                Button("") { withAnimation(.snappy) { confirmingDiscard = false } }
                    .keyboardShortcut(.cancelAction)
                    .hidden()
            }
            .transition(.opacity)
        } else {
            normalFooter
        }
    }

    private var normalFooter: some View {
        HStack(spacing: 10) {
            // Undoable (Recently Deleted keeps it 30 days), so no confirmation.
            Button(deleteButton, role: .destructive) { delete() }
                .glassButton()
                .controlSize(.large)
                .foregroundStyle(Color.danger)
            Spacer()
            Button("Cancel", action: requestClose)
                .keyboardShortcut(.cancelAction)
                .glassButton()
                .controlSize(.large)
            Button(action: save) {
                HStack(spacing: 8) {
                    Text("Save Changes")
                    Text("↵").font(.callout.weight(.semibold)).opacity(0.6)
                }
            }
            // A button label never wraps.
            .lineLimit(1)
            .fixedSize()
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
        case .file: "Edit File"
        case .project: "Edit Project"
        }
    }

    /// What it is and, when Slinky can tell, which service: "Key or token · GitHub".
    private var kindLabel: String {
        let service = IconResolver.shared.service(for: iconSubject)?.name
        switch target {
        case .key:
            return ["Key or token", service].compactMap { $0 }.joined(separator: " · ")
        case let .kept(id):
            let kind = model.document.kept.first { $0.id == id }?.kind.title ?? "Recovery key"
            return [kind, service].compactMap { $0 }.joined(separator: " · ")
        case .codes:
            return ["Recovery codes", service].compactMap { $0 }.joined(separator: " · ")
        case let .file(id):
            let kind = model.document.secretFiles.first { $0.id == id }?.kind.title ?? "File"
            return [kind, service].compactMap { $0 }.joined(separator: " · ")
        case let .project(id):
            let n = model.document.projects.first { $0.id == id }?.variables.count ?? 0
            return "Project · \(n) \(n == 1 ? "variable" : "variables")"
        }
    }

    private var deleteButton: String {
        if case .project = target { return "Delete Project" }
        return "Delete"
    }

    /// Everything the panel can change, to tell whether closing would lose something.
    private struct Snapshot: Equatable {
        var name, from, note, link, newValue, newCodes, issuerID, keyID: String
        var replacing, hasExpiry, resetUsed: Bool
        var expiry: Date
        var policy: AgentPolicy
        var keptKind: KeptKind
        var folders: [String]
        var service: String?
    }

    private var snapshot: Snapshot {
        Snapshot(name: name, from: from, note: note, link: link, newValue: newValue, newCodes: newCodes, issuerID: issuerID, keyID: keyID,
                 replacing: replacing, hasExpiry: hasExpiry, resetUsed: resetUsed, expiry: expiry,
                 policy: policy, keptKind: keptKind, folders: folders, service: service)
    }

    private func requestClose() {
        guard let original, snapshot != original else { close(); return }
        withAnimation(.snappy) { confirmingDiscard = true }
    }

    /// The link as saved: https only. Something that isn't a web address is dropped rather than stored.
    private var savedLink: String? { Links.normalized(link) }

    /// The header icon follows the edits as they're typed, keeping the person's own icon choice.
    private var iconSubject: IconSubject {
        let doc = model.document
        var subject = IconSubject(name: name, from: from.isEmpty ? nil : from, link: link.isEmpty ? nil : link, service: service)
        switch target {
        case let .key(id):
            subject.provider = doc.keys.first { $0.id == id }?.provider
            subject.choice = doc.keys.first { $0.id == id }?.icon
        case let .kept(id): subject.choice = doc.kept.first { $0.id == id }?.icon
        case let .codes(id): subject.choice = doc.codeSets.first { $0.id == id }?.icon
        case let .file(id): subject.choice = doc.secretFiles.first { $0.id == id }?.icon
        case .project: subject.choice = .monogram
        }
        return subject
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
        // "Make a New Key on …" opens Edit with Replace ready for the new value.
        if model.editReplacing { replacing = true; model.editReplacing = false }
        switch target {
        case let .key(id):
            guard let key = model.document.keys.first(where: { $0.id == id }) else { return }
            name = key.name
            note = key.note ?? ""
            link = key.link ?? ""
            service = key.service
            hasExpiry = key.expires != nil
            expiry = key.expires ?? Calendar.current.date(byAdding: .day, value: 90, to: .now) ?? .now
            policy = key.agentPolicy
        case let .kept(id):
            guard let item = model.document.kept.first(where: { $0.id == id }) else { return }
            name = item.label
            from = item.from ?? ""
            note = item.note ?? ""
            link = item.link ?? ""
            service = item.service
            keptKind = item.kind == .setupKey ? .setupKey : .recoveryKey
        case let .codes(id):
            guard let set = model.document.codeSets.first(where: { $0.id == id }) else { return }
            name = set.account
            from = set.username ?? ""
            note = set.note ?? ""
            link = set.link ?? ""
            service = set.service
        case let .file(id):
            guard let file = model.document.secretFiles.first(where: { $0.id == id }) else { return }
            name = file.name
            note = file.note ?? ""
            link = file.link ?? ""
            service = file.service
            issuerID = file.fields["Issuer ID"] ?? ""
            keyID = file.fields["Key ID"] ?? ""
        case let .project(id):
            guard let p = model.document.projects.first(where: { $0.id == id }) else { return }
            name = p.name
            folders = p.folders
        }
        original = snapshot
    }

    private func save() {
        guard canSave else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch target {
        case let .key(id):
            guard var key = model.document.keys.first(where: { $0.id == id }) else { return }
            let before = key
            key.name = trimmedName
            key.note = note.isEmpty ? nil : note
            key.link = savedLink
            key.service = service
            key.expires = hasExpiry ? expiry : nil
            key.agentPolicy = policy
            if replacing, !value.isEmpty {
                key.value = value
                let detection = Detector.detect(value)
                key.provider = detection?.provider ?? key.provider
                key.isLive = detection?.isLive ?? false
            }
            model.update(key)
            if replacing, !value.isEmpty, value != before.value { model.replaced(before, with: key) }
        case let .kept(id):
            guard var item = model.document.kept.first(where: { $0.id == id }) else { return }
            item.label = trimmedName
            item.from = from.isEmpty ? nil : from
            item.note = note.isEmpty ? nil : note
            item.link = savedLink
            item.service = service
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
            set.note = note.isEmpty ? nil : note
            set.link = savedLink
            set.service = service
            if replacing, parsedCodes.count >= 2 {
                set.codes = parsedCodes
                set.used = []
                set.regenerated = .now
            }
            model.update(set)
        case let .file(id):
            guard var file = model.document.secretFiles.first(where: { $0.id == id }) else { return }
            file.name = trimmedName
            file.note = note.isEmpty ? nil : note
            file.link = savedLink
            file.service = service
            let issuer = issuerID.trimmingCharacters(in: .whitespaces), kid = keyID.trimmingCharacters(in: .whitespaces)
            if file.kind == .appStoreConnectKey {
                file.fields["Issuer ID"] = issuer.isEmpty ? nil : issuer
                file.fields["Key ID"] = kid.isEmpty ? nil : kid
            }
            model.update(file)
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
        case let .file(id): model.deleteFile(id)
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

/// A text field in a FieldRow, named after the row for VoiceOver ("Name", "Note"), not after its example text.
private struct PlainField: View {
    @Environment(\.fieldRowLabel) private var label
    @Binding var text: String
    let prompt: String
    var mono = false
    var max: Int

    var body: some View {
        TextField(label, text: $text, prompt: Text(prompt))
            .labelsHidden()
            .textFieldStyle(.plain)
            .font(mono ? .body.monospaced().weight(.medium) : .body)
            .limit($text, to: max)
    }
}

extension EnvironmentValues {
    @Entry var fieldRowLabel = ""
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
                    .environment(\.fieldRowLabel, label)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            if !last { Divider().padding(.leading, 16) }
        }
    }
}
