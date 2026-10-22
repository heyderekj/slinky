import AppKit
import SlinkyCoreShared
import SwiftUI

// MARK: Rows

/// One line per item: icon, name, a quiet second line, the short peek, and Copy always in reach.
struct ItemRowLayout<Tags: View, Action: View>: View {
    var icon: IconSubject
    var title: String
    var mono = false
    var subtitle: String
    var peek: String?
    /// A quiet symbol tile instead of initials, for a list where most items have no service of their own.
    var plainSymbol: String? = nil
    @ViewBuilder var tags: Tags
    @ViewBuilder var action: Action

    var body: some View {
        // Roomy, like Passwords: a 32-point icon, the name in semibold, a quiet second line.
        HStack(spacing: 12) {
            if let plainSymbol {
                Image(systemName: plainSymbol)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8, style: .continuous))
            } else {
                ServiceIcon(subject: icon, size: 32)
            }
            VStack(alignment: .leading, spacing: 2) {
                // Cut in the middle: names that share a start (…_EU_WEST, …_US_EAST) stay tellable apart.
                Text(title)
                    .font(mono ? .body.monospaced().weight(.semibold) : .body.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            tags
            if let peek {
                // Whole or not at all: in a narrow list a cut-off peek ("•", "c") says nothing.
                ViewThatFits(in: .horizontal) {
                    Text(peek)
                        .font(.callout.monospaced())
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                    Color.clear.frame(width: 0, height: 0)
                }
                .accessibilityHidden(true)
            }
            action
                .buttonStyle(.borderless)
                .labelStyle(.titleAndIcon)
                .controlSize(.small)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, 6)
    }
}

struct KeyRow: View {
    @Environment(AppModel.self) private var model
    let key: Key

    var body: some View {
        ItemRowLayout(icon: key.iconSubject, title: key.name, mono: true,
                      subtitle: [key.provider ?? "Key or token", Links.host(of: key.link)].compactMap { $0 }.joined(separator: " · "),
                      peek: Peek.of(key.value)) {
            if key.isLive { Chip(text: "live", style: .live) }
            if let chip = ExpiryChip.text(key.expires) { Chip(text: chip, style: .warn) }
        } action: {
            CopyButton { model.copy(key.value, label: key.name, provider: key.provider) }
        }
    }
}

struct CodeSetRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.backgroundProminence) private var prominence
    let set: CodeSet

    var body: some View {
        ItemRowLayout(icon: set.iconSubject, title: set.account,
                      subtitle: set.username ?? "Recovery codes", peek: nil) {
            Text("\(set.remaining) of \(set.codes.count) left")
                .font(.caption.monospacedDigit())
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText(value: Double(set.remaining)))
                .animation(.snappy, value: set.remaining)
                // Amber when low, but plain on a selected row, where colored text on the highlight is hard to read.
                .foregroundStyle(set.isLow && prominence != .increased ? AnyShapeStyle(Color.attention) : AnyShapeStyle(.secondary))
        } action: {
            CopyButton(title: "Copy Next") {
                if let next = set.nextUnused { model.useCode(next, in: set.id) }
            }
            .disabled(set.nextUnused == nil)
            .help("Copy the next unused code and cross it off")
        }
    }
}

struct FileRow: View {
    @Environment(AppModel.self) private var model
    let file: SecretFile

    var body: some View {
        ItemRowLayout(icon: file.iconSubject, title: file.name, subtitle: "\(file.kind.title) · \(file.filename)", peek: nil) {
            EmptyView()
        } action: {
            if let text = file.text {
                CopyButton { model.copy(text, label: file.name) }
            } else {
                Button { FileExport.save(file) } label: { Label("Save", systemImage: "square.and.arrow.down") }
            }
        }
    }
}

struct KeptRow: View {
    @Environment(AppModel.self) private var model
    let item: KeptItem

    var body: some View {
        ItemRowLayout(icon: item.iconSubject, title: item.label,
                      subtitle: [item.kind.title, item.from.map { "From \($0)" }].compactMap { $0 }.joined(separator: " · "),
                      peek: Peek.of(item.value)) {
            EmptyView()
        } action: {
            CopyButton { model.copy(item.value, label: item.label) }
        }
    }
}

enum ExpiryChip {
    /// "Expiring soon" everywhere (this chip, the library filter, Health): within 14 days.
    static let soonDays = 14

    static func isSoon(_ date: Date?, now: Date = .now) -> Bool {
        guard let date else { return false }
        return date < (Calendar.current.date(byAdding: .day, value: soonDays, to: now) ?? now)
    }

    /// Only when it matters: expired, or due within 14 days.
    static func text(_ date: Date?) -> String? {
        guard let date else { return nil }
        if date < .now { return "expired" }
        guard isSoon(date) else { return nil }
        return "expires \(date.formatted(.relative(presentation: .named)))"
    }
}

// MARK: Actions

/// The same actions in the row's context menu and the details pane.
struct ItemActions: View {
    @Environment(AppModel.self) private var model
    let ref: LibraryRef

    var body: some View {
        switch ref {
        case let .key(id):
            if let key = model.document.keys.first(where: { $0.id == id }) {
                Button("Copy") { model.copy(key.value, label: key.name, provider: key.provider) }
                Button("Copy as \(key.name)=…") { model.copy("\(key.name)=\(key.value)", label: key.name, provider: key.provider) }
                Button("Copy Name") { model.copyName(key.name) }
                linkButton(key.link)
            }
        case let .codes(id):
            if let set = model.document.codeSets.first(where: { $0.id == id }) {
                Button("Copy Next Code") { if let next = set.nextUnused { model.useCode(next, in: id) } }
                    .disabled(set.nextUnused == nil)
                linkButton(set.link)
            }
        case let .kept(id):
            if let item = model.document.kept.first(where: { $0.id == id }) {
                Button("Copy") { model.copy(item.value, label: item.label) }
                linkButton(item.link)
            }
        case let .file(id):
            if let file = model.document.secretFiles.first(where: { $0.id == id }) {
                if let text = file.text { Button("Copy Contents") { model.copy(text, label: file.name) } }
                Button("Save a Copy…") { FileExport.save(file) }
                linkButton(file.link)
            }
        }
        Divider()
        Button("Edit…") { model.editing = ref.editTarget }
        Button("Choose Icon…") { model.choosingIcon = ref }
        Button("Delete", role: .destructive) {
            switch ref {
            case let .key(id): model.deleteKey(id)
            case let .codes(id): model.deleteCodeSet(id)
            case let .kept(id): model.deleteKept(id)
            case let .file(id): model.deleteFile(id)
            }
        }
    }

    @ViewBuilder
    private func linkButton(_ link: String?) -> some View {
        if let url = Self.url(link) {
            Button("Open \(url.host() ?? "Link")") { NSWorkspace.shared.open(url) }
        }
    }

    /// Only https links open. Anything else saved before the rule stays text.
    static func url(_ link: String?) -> URL? {
        guard let link, let normalized = Links.normalized(link), normalized == link else { return nil }
        return URL(string: normalized)
    }

    static func copy(_ ref: LibraryRef, model: AppModel) {
        switch ref {
        case let .key(id):
            if let key = model.document.keys.first(where: { $0.id == id }) { model.copy(key.value, label: key.name, provider: key.provider) }
        case let .codes(id):
            if let next = model.document.codeSets.first(where: { $0.id == id })?.nextUnused { model.useCode(next, in: id) }
        case let .kept(id):
            if let item = model.document.kept.first(where: { $0.id == id }) { model.copy(item.value, label: item.label) }
        case let .file(id):
            if let file = model.document.secretFiles.first(where: { $0.id == id }), let text = file.text { model.copy(text, label: file.name) }
        }
    }
}

// MARK: Details pane

struct ItemDetail: View {
    @Environment(AppModel.self) private var model
    let ref: LibraryRef

    var body: some View {
        switch ref {
        case let .key(id):
            if let key = model.document.keys.first(where: { $0.id == id }) { keyDetail(key) }
        case let .codes(id):
            if let set = model.document.codeSets.first(where: { $0.id == id }) { codesDetail(set) }
        case let .kept(id):
            if let item = model.document.kept.first(where: { $0.id == id }) { keptDetail(item) }
        case let .file(id):
            if let file = model.document.secretFiles.first(where: { $0.id == id }) { fileDetail(file) }
        }
    }

    @ViewBuilder
    private func fileButtons(_ file: SecretFile) -> some View {
        if let text = file.text {
            CopyButton(title: "Copy Contents") { model.copy(text, label: file.name) }.glassProminentButton().fixedSize()
        }
        Button("Save a Copy…") { FileExport.save(file) }.glassButton().fixedSize()
    }

    private func fileDetail(_ file: SecretFile) -> some View {
        DetailScaffold(icon: file.iconSubject, title: file.name, kind: file.kind.title, ref: ref) {
            Section {
                // File names differ at the end (version, extension), so they're cut in the middle.
                LabeledContent("File") { Text(file.filename).lineLimit(1).truncationMode(.middle).help(file.filename) }
                LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: Int64(file.data.count), countStyle: .file))
                ForEach(file.fields.keys.sorted(), id: \.self) { key in
                    LabeledContent(key) { Text(file.fields[key] ?? "").textSelection(.enabled).font(.system(.body, design: .monospaced)) }
                }
                // Side by side when the panel has room, one above the other when it doesn't.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { fileButtons(file); Spacer(minLength: 0) }
                    VStack(alignment: .leading, spacing: 8) { fileButtons(file) }
                }
            }
            if file.kind == .appStoreConnectKey {
                Section {
                    Button("Save a notarytool Profile…") { FileExport.notaryProfile(file, model: model) }
                        .disabled(file.fields["Issuer ID"] == nil)
                } footer: {
                    Text(file.fields["Issuer ID"] == nil ? "Add the Issuer ID with Edit first." :
                            "So xcrun notarytool can notarize with --keychain-profile, without the .p8 sitting in a folder.")
                }
            }
            NoteAndLink(note: file.note, link: file.link)
            Section { Dates(created: file.created, updated: file.updated) }
        }
    }

    private func keyDetail(_ key: Key) -> some View {
        DetailScaffold(icon: key.iconSubject, title: key.name, mono: true, kind: "Key or token", ref: ref) {
            Section {
                RevealField(value: key.value)
                // One clear Copy; the .env form is a click away in the menu instead of a second, truncated button.
                HStack(spacing: 8) {
                    CopyButton { model.copy(key.value, label: key.name, provider: key.provider) }
                        .glassProminentButton()
                    Menu {
                        Button("Copy as \(key.name)=…") { model.copy("\(key.name)=\(key.value)", label: key.name, provider: key.provider) }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .glassButton()
                    .help("More ways to copy")
                    Spacer(minLength: 0)
                    if key.isLive { Chip(text: "live", style: .live) }
                }
                .controlSize(.regular)
            }
            Section {
                LabeledContent("Expires", value: key.expires.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Never")
                LabeledContent("AI agents", value: key.agentPolicy.title)
                Dates(created: key.created, updated: key.updated)
            }
            RotateRow(subject: key.iconSubject, ref: ref, what: "Key")
            NoteAndLink(note: key.note, link: key.link)
        }
    }

    private func codesDetail(_ set: CodeSet) -> some View {
        DetailScaffold(icon: set.iconSubject, title: set.account, kind: ["Recovery codes", set.username].compactMap { $0 }.joined(separator: " · "), ref: ref) {
            Section {
                if set.isLow {
                    Label(set.remaining == 0 ? "No codes left. Make new ones." : "Only \(set.remaining) left. Consider making new ones.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(Color.attention)
                }
                CodeGrid(set: set)
            } header: {
                Text("\(set.remaining) of \(set.codes.count) left · click a code to copy and cross it off")
                    .contentTransition(.numericText(value: Double(set.remaining)))
                    .animation(.snappy, value: set.remaining)
            }
            RotateRow(subject: set.iconSubject, ref: ref, what: "Codes")
            NoteAndLink(note: set.note, link: set.link)
            Section { Dates(created: set.created, updated: set.regenerated, updatedLabel: "New codes") }
        }
    }

    private func keptDetail(_ item: KeptItem) -> some View {
        DetailScaffold(icon: item.iconSubject, title: item.label,
                       kind: [item.kind.title, item.from.map { "From \($0)" }].compactMap { $0 }.joined(separator: " · "), ref: ref) {
            Section {
                RevealField(value: item.value)
                HStack(spacing: 8) {
                    CopyButton { model.copy(item.value, label: item.label) }
                        .glassProminentButton()
                    if item.kind == .recoveryKey {
                        if item.printedCopy {
                            Label("Printed", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("Print…") {
                                RecoveryPrinter.print(item.value, title: item.label)
                                model.markPrinted(item.id)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .glassButton()
            }
            NoteAndLink(note: item.note, link: item.link)
            Section { Dates(created: item.created, updated: nil) }
        }
    }
}

/// Header, a grouped form for the sections, then Edit and Delete at the bottom.
private struct DetailScaffold<Content: View>: View {
    @Environment(AppModel.self) private var model
    var icon: IconSubject
    var title: String
    var mono = false
    var kind: String
    var ref: LibraryRef
    @ViewBuilder var content: Content

    private var serviceChip: some View {
        ServiceChip(selection: Binding(get: { icon.service }, set: { model.setService($0, for: ref) }),
                    subject: icon, automatic: IconResolver.shared.matched(icon), inline: true)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { model.choosingIcon = ref } label: { ServiceIcon(subject: icon, size: 44) }
                    .buttonStyle(.plain)
                    .help("Choose Icon…")
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold, design: mono ? .monospaced : .default))
                        .lineLimit(2)
                        .textSelection(.enabled)
                    // What it is and where it lives, on one line when they fit; the panel is narrow, so otherwise two.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 4) {
                            Text(kind).foregroundStyle(.secondary).lineLimit(1)
                            Text("·").foregroundStyle(.tertiary)
                            serviceChip
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            serviceChip
                        }
                    }
                    .font(.callout)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            WebsiteIconButton(subject: icon, ref: ref)

            Form { content }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)

            HStack {
                Button("Delete", role: .destructive) {
                    switch ref {
                    case let .key(id): model.deleteKey(id)
                    case let .codes(id): model.deleteCodeSet(id)
                    case let .kept(id): model.deleteKept(id)
                    case let .file(id): model.deleteFile(id)
                    }
                    model.librarySelection = nil
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("Move to Recently Deleted")
                Spacer()
                Button { model.editing = ref.editTarget } label: { Label("Edit", systemImage: "pencil") }
                    .glassButton()
                    .controlSize(.large)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }
}

/// "Load Icon from github.com": one item, one request, only when asked. Shown while the item has no app
/// icon or logo and the setting to load them automatically is off.
private struct WebsiteIconButton: View {
    @Environment(AppModel.self) private var model
    let subject: IconSubject
    let ref: LibraryRef
    @State private var loading = false
    @State private var failed = false

    var body: some View {
        let resolver = IconResolver.shared
        if !Preferences.shared.loadWebsiteIcons, case .monogram = resolver.resolve(subject),
           subject.choice != .monogram, let host = resolver.websiteHost(subject), !resolver.hasSiteIcon(host) {
            HStack(spacing: 6) {
                Button(loading ? "Loading…" : "Load Icon from \(host)") {
                    loading = true
                    Task {
                        let ok = await resolver.loadSiteIcon(host)
                        loading = false
                        failed = !ok
                        if ok { model.setIcon(.website(host), for: ref) }
                    }
                }
                .buttonStyle(.link)
                .disabled(loading)
                .help("Asks \(host) for its icon. Nothing else is sent.")
                if failed { Text("\(host) didn't have one Slinky can use.").foregroundStyle(.secondary) }
                Spacer()
            }
            .font(.caption)
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }
}

/// "Make a New Key on GitHub…": the service's own key page, then Edit with Replace ready. Shown when Slinky knows
/// where to go (the service's key page, the item's link, or the service's site).
private struct RotateRow: View {
    @Environment(AppModel.self) private var model
    let subject: IconSubject
    let ref: LibraryRef
    let what: String

    var body: some View {
        if model.rotationURL(for: subject) != nil {
            let service = IconResolver.shared.service(for: subject)?.name
            Section {
                Button("Make New \(what) on \(service ?? "the Website")…") { model.startRotation(ref) }
            } footer: {
                Text(what == "Codes" ? "Opens the page where you make new codes, and Edit to paste them. The old ones stop working there."
                                     : "Opens the page where you make keys, and Edit to paste the new one. The old one stays in Recently Deleted for 30 days, and projects using it get the new one.")
            }
        }
    }
}

private struct NoteAndLink: View {
    var note: String?
    var link: String?

    var body: some View {
        if note != nil || link != nil {
            Section {
                if let note, !note.isEmpty {
                    Text(note).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                if let link {
                    HStack {
                        Text(Links.host(of: link) ?? link).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if let url = ItemActions.url(link) {
                            Button("Open") { NSWorkspace.shared.open(url) }
                                .controlSize(.small)
                                .help(url.absoluteString)
                        }
                    }
                }
            }
        }
    }
}

private struct Dates: View {
    var created: Date
    var updated: Date?
    var updatedLabel = "Changed"

    var body: some View {
        LabeledContent("Added", value: created.formatted(date: .abbreviated, time: .omitted))
        if let updated, abs(updated.timeIntervalSince(created)) > 60 {
            LabeledContent(updatedLabel, value: updated.formatted(date: .abbreviated, time: .omitted))
        }
    }
}

/// Every code in a set. Click one to copy it and cross it off.
struct CodeGrid: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let set: CodeSet

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
            ForEach(Array(set.codes.enumerated()), id: \.offset) { index, code in
                let used = set.used.contains(index)
                Button {
                    model.useCode(index, in: set.id)
                } label: {
                    HStack(spacing: 4) {
                        // One line, so every tile is the same height: shrink a little first, then cut in the middle.
                        Text(code)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .truncationMode(.middle)
                            .foregroundStyle(used ? Color.secondary.opacity(0.6) : Color.primary)
                            // Crossed off like a printed list: a line drawn left to right, then the checkmark.
                            .overlay {
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundStyle(Color.secondary.opacity(0.7))
                                    .scaleEffect(x: used ? 1 : 0, anchor: .leading)
                            }
                        if used {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .drawOnTransition()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.paper, in: .rect(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(used)
                .help(used ? "Used" : "Copy and cross off")
                .accessibilityLabel(used ? "\(code), used" : "Copy code \(code)")
            }
        }
        // Lives here, not inside the tiles: the line and checkmark were set without an animation, so they just appeared.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: set.used)
    }
}


extension SecretFile {
    /// The contents as text, for keys and certificates that are text (a .p8, a .pem). nil for binary files.
    var text: String? {
        guard !data.contains(0), let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }
}

/// Getting a secret file back out, only when the person asks.
@MainActor
enum FileExport {
    /// Writes a copy where the person chooses, readable by them only.
    static func save(_ file: SecretFile) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.filename
        panel.title = "Save a Copy of \(file.name)"
        panel.message = "This writes the secret to a file. Delete it when you're done."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        FileManager.default.createFile(atPath: url.path, contents: file.data, attributes: [.posixPermissions: 0o600])
        AppModel.shared.show("Saved a copy of \(file.filename). Only you can read it.")
    }

    /// Asks for a profile name, then saves a notarytool keychain profile from this App Store Connect key.
    static func notaryProfile(_ file: SecretFile, model: AppModel) {
        let alert = NSAlert()
        alert.messageText = "Save a notarytool Profile"
        alert.informativeText = "notarytool keeps it in your keychain. Then notarize with: xcrun notarytool submit … --keychain-profile NAME"
        let field = NSTextField(string: "slinky-notary")
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Save Profile")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let me = Peer(pid: 0, chain: [], app: nil, agent: nil)
        Task {
            let r = await model.notarizeProfile(Broker.Request(op: .notarize, name: field.stringValue, text: file.name), peer: me)
            model.show(r.message ?? (r.ok ? "Saved." : "Couldn't save the profile."), style: r.ok ? .success : .info)
        }
    }
}
