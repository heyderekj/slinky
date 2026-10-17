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
    @ViewBuilder var tags: Tags
    @ViewBuilder var action: Action

    var body: some View {
        HStack(spacing: 10) {
            ServiceIcon(subject: icon, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium, design: mono ? .monospaced : .default))
                    .lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            tags
            if let peek {
                Text(peek)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }
            action
                .buttonStyle(.borderless)
                .labelStyle(.titleAndIcon)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
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
    let set: CodeSet

    var body: some View {
        ItemRowLayout(icon: set.iconSubject, title: set.account,
                      subtitle: set.username ?? "Recovery codes", peek: nil) {
            Text("\(set.remaining) of \(set.codes.count) left")
                .font(.caption.monospacedDigit())
                .foregroundStyle(set.isLow ? Color.orange : Color.secondary)
        } action: {
            CopyButton(title: "Copy Next") {
                if let next = set.nextUnused { model.useCode(next, in: set.id) }
            }
            .disabled(set.nextUnused == nil)
            .help("Copy the next unused code and cross it off")
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
    /// Only when it matters: expired, or due within 30 days.
    static func text(_ date: Date?) -> String? {
        guard let date else { return nil }
        if date < .now { return "expired" }
        guard date < Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now else { return nil }
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
        }
        Divider()
        Button("Edit…") { model.editing = ref.editTarget }
        Button("Choose Icon…") { model.choosingIcon = ref }
        Button("Delete", role: .destructive) {
            switch ref {
            case let .key(id): model.deleteKey(id)
            case let .codes(id): model.deleteCodeSet(id)
            case let .kept(id): model.deleteKept(id)
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
        }
    }

    private func keyDetail(_ key: Key) -> some View {
        DetailScaffold(icon: key.iconSubject, title: key.name, mono: true, kind: key.provider ?? "Key or token", ref: ref) {
            Section {
                RevealField(value: key.value)
                HStack {
                    CopyButton { model.copy(key.value, label: key.name, provider: key.provider) }
                    CopyButton(title: "Copy as \(key.name)=…") { model.copy("\(key.name)=\(key.value)", label: key.name, provider: key.provider) }
                        .lineLimit(1)
                }
                .glassButton()
                .controlSize(.small)
            }
            Section {
                if key.isLive { LabeledContent("Kind") { Chip(text: "live", style: .live) } }
                LabeledContent("Expires", value: key.expires.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Never")
                LabeledContent("AI agents", value: key.agentPolicy.title)
            }
            NoteAndLink(note: key.note, link: key.link)
            Dates(created: key.created, updated: key.updated)
        }
    }

    private func codesDetail(_ set: CodeSet) -> some View {
        DetailScaffold(icon: set.iconSubject, title: set.account, kind: set.username ?? "Recovery codes", ref: ref) {
            Section {
                if set.isLow {
                    Label("Only \(set.remaining) left. Consider making new ones.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                }
                CodeGrid(set: set)
            } header: {
                Text("\(set.remaining) of \(set.codes.count) left · click a code to copy and cross it off")
            }
            NoteAndLink(note: set.note, link: set.link)
            Dates(created: set.created, updated: set.regenerated, updatedLabel: "New codes")
        }
    }

    private func keptDetail(_ item: KeptItem) -> some View {
        DetailScaffold(icon: item.iconSubject, title: item.label,
                       kind: [item.kind.title, item.from.map { "From \($0)" }].compactMap { $0 }.joined(separator: " · "), ref: ref) {
            Section {
                RevealField(value: item.value)
                HStack {
                    CopyButton { model.copy(item.value, label: item.label) }
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
                }
                .glassButton()
                .controlSize(.small)
            }
            NoteAndLink(note: item.note, link: item.link)
            Dates(created: item.created, updated: nil)
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

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { model.choosingIcon = ref } label: { ServiceIcon(subject: icon, size: 44) }
                    .buttonStyle(.plain)
                    .help("Choose Icon…")
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: mono ? .monospaced : .default))
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Text(kind).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
                    }
                    model.librarySelection = nil
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                Spacer()
                Button("Edit…") { model.editing = ref.editTarget }
                    .glassButton()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
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
        Section {
            LabeledContent("Added", value: created.formatted(date: .abbreviated, time: .omitted))
            if let updated, abs(updated.timeIntervalSince(created)) > 60 {
                LabeledContent(updatedLabel, value: updated.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .foregroundStyle(.secondary)
    }
}

/// Every code in a set. Click one to copy it and cross it off.
struct CodeGrid: View {
    @Environment(AppModel.self) private var model
    let set: CodeSet

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
            ForEach(Array(set.codes.enumerated()), id: \.offset) { index, code in
                let used = set.used.contains(index)
                Button {
                    model.useCode(index, in: set.id)
                } label: {
                    HStack(spacing: 4) {
                        Text(code)
                            .font(.system(size: 12, design: .monospaced))
                            .strikethrough(used)
                            .foregroundStyle(used ? Color.secondary.opacity(0.6) : Color.primary)
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
    }
}
