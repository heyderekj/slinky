import SlinkyCoreShared
import SwiftUI

/// Layout B: the shelf. Cards shaped like what they hold.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    let filter: LibraryFilter
    /// The All Items heading follows the animation: what Slinky does with each example, then the tagline.
    @State private var playing: Int?

    private let columns = [GridItem(.adaptive(minimum: 270, maximum: 420), spacing: 14, alignment: .top)]

    var body: some View {
        Group {
            if isEmpty {
                empty
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if filter != .recovery, !model.document.keys.isEmpty {
                            section(filter == .all ? "Keys & Tokens" : nil) { ForEach(model.document.keys) { KeyCard(key: $0) } }
                        }
                        if filter != .keys, !model.document.codeSets.isEmpty {
                            section("Recovery Codes") { ForEach(model.document.codeSets) { CodeSetCard(set: $0) } }
                        }
                        if filter != .keys, !model.document.kept.isEmpty {
                            section("Recovery Keys") { ForEach(model.document.kept) { KeptCard(item: $0) } }
                        }
                    }
                    .padding(18)
                }
            }
        }
        .navigationTitle(filter.title)
        .navigationSubtitle(subtitle)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String?, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title).font(.headline).foregroundStyle(.secondary).padding(.leading, 2)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) { content() }
        }
    }

    private var isEmpty: Bool {
        switch filter {
        case .all: model.document.keys.isEmpty && model.document.codeSets.isEmpty && model.document.kept.isEmpty
        case .keys: model.document.keys.isEmpty
        case .recovery: model.document.codeSets.isEmpty && model.document.kept.isEmpty
        }
    }

    private var subtitle: String {
        switch filter {
        case .all:
            return "\(model.document.keys.count + model.document.codeSets.count + model.document.kept.count) items"
        case .keys:
            return "API keys and access tokens your software uses"
        case .recovery:
            let low = model.document.codeSets.filter(\.isLow).count
            return "Codes and keys that get you back into your accounts" + (low > 0 ? " · \(low) running low" : "")
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            VaultIdleAnimation(samples: samples) { index in
                withAnimation(.smooth(duration: 0.3)) { playing = index }
            }
            // One line, so the layout under it never jumps as the heading changes.
            Text(emptyTitle)
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: 540)
                .contentTransition(.opacity)
                .id(emptyTitle)
                .transition(.opacity.combined(with: .offset(y: 4)))
            Text(emptyLine).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 330)
            Button {
                model.tuckPrefill = ""
                model.tuckProject = nil
                model.showTuck = true
            } label: {
                Label("Add Item", systemImage: "plus")
            }
            .glassProminentButton()
            .controlSize(.extraLarge)
            .font(.title3.weight(.semibold))
            .padding(.top, 8)
            if filter == .all {
                Button("Keep keys somewhere else? Import them…") { model.beginImport() }
                    .buttonStyle(.link)
                    .font(.callout)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        switch filter {
        case .all: playing.flatMap { samples.indices.contains($0) ? samples[$0].headline : nil } ?? VaultIdleAnimation.restHeadline
        case .keys: "No keys or tokens yet"
        case .recovery: "No recovery codes or keys yet"
        }
    }

    private var emptyLine: String {
        switch filter {
        case .all: "Paste a key, recovery codes or a .env line with ⌘N. Slinky sorts it for you."
        case .keys: "For the API keys and access tokens your software and AI tools use."
        case .recovery: "For backup codes and recovery keys that get you back into your accounts."
        }
    }

    /// Lead the animation with the kind of item this view holds.
    private var samples: [VaultIdleAnimation.Sample] {
        let s = VaultIdleAnimation.defaultSamples   // API key, project variable, recovery codes, recovery key
        switch filter {
        case .all, .keys: return s
        case .recovery: return [s[2], s[3], s[0], s[1]]
        }
    }
}

private struct CardChrome<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .contentShape(.rect(cornerRadius: 18))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.separator.opacity(0.5), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 6)
    }
}

struct CodeSetCard: View {
    @Environment(AppModel.self) private var model
    let set: CodeSet

    var body: some View {
        CardChrome {
            HStack(alignment: .top, spacing: 10) {
                Monogram(text: set.account)
                VStack(alignment: .leading, spacing: 2) {
                    Text("RECOVERY CODES").font(.system(size: 9.5, weight: .bold)).tracking(0.5).foregroundStyle(.tertiary)
                    Text(set.account).font(.headline)
                    if let user = set.username { Text(user).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(set.remaining)").font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(set.isLow ? Color.orange : Color.primary)
                    Text("left").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if set.isLow {
                Label("Only \(set.remaining) codes left. Consider generating new ones.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
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
                            .background(.background.secondary, in: .rect(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .disabled(used)
                    .help(used ? "Used" : "Copy and cross off")
                    .accessibilityLabel(used ? "\(code), used" : "Copy code \(code)")
                }
            }
            HStack {
                if let date = set.regenerated {
                    Text("Added \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Menu {
                    Button("Edit…") { model.editing = .codes(set.id) }
                    Divider()
                    Button("Remove", role: .destructive) { model.deleteCodeSet(set.id) }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize()
            }
        .contextMenu { Button("Edit…") { model.editing = .codes(set.id) } }
        }
    }
}

struct KeptCard: View {
    @Environment(AppModel.self) private var model
    let item: KeptItem

    var body: some View {
        CardChrome {
            HStack(alignment: .top, spacing: 10) {
                Monogram(text: item.from ?? item.label)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.kind.title.uppercased()).font(.system(size: 9.5, weight: .bold)).tracking(0.5).foregroundStyle(.tertiary)
                    Text(item.label).font(.headline)
                    if let from = item.from { Text("From \(from)").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
            }
            RevealField(value: item.value)
            HStack {
                CopyButton { model.copy(item.value, label: item.label) }
                    .glassButton().controlSize(.small)
                if item.kind == .recoveryKey {
                    if item.printedCopy {
                        Label("Printed", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Print…") {
                            RecoveryPrinter.print(item.value, title: item.label)
                            model.markPrinted(item.id)
                        }
                        .glassButton().controlSize(.small)
                    }
                }
                Spacer()
                Menu {
                    Button("Edit…") { model.editing = .kept(item.id) }
                    Divider()
                    Button("Remove", role: .destructive) { model.deleteKept(item.id) }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize()
            }
        .contextMenu { Button("Edit…") { model.editing = .kept(item.id) } }
        }
    }
}

struct KeyCard: View {
    @Environment(AppModel.self) private var model
    let key: Key

    var body: some View {
        CardChrome {
            HStack(alignment: .top, spacing: 10) {
                Monogram(text: key.provider ?? key.name)
                VStack(alignment: .leading, spacing: 2) {
                    Text("KEY OR TOKEN").font(.system(size: 9.5, weight: .bold)).tracking(0.5).foregroundStyle(.tertiary)
                    Text(key.name).font(.system(size: 13, weight: .semibold, design: .monospaced))
                    if let provider = key.provider { Text(provider).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if key.isLive { Chip(text: "live", style: .live) }
            }
            RevealField(value: key.value)
            HStack(spacing: 6) {
                if let expires = key.expires {
                    Chip(text: expires < .now ? "expired" : "expires \(expires.formatted(.relative(presentation: .named)))", style: .warn)
                }
                Chip(text: key.agentPolicy.title, style: .plain)
                Spacer()
                CopyButton { model.copy(key.value, label: key.name) }
                    .glassButton().controlSize(.small)
                Menu {
                    Button("Edit…") { model.editing = .key(key.id) }
                    Divider()
                    Button("Remove", role: .destructive) { model.deleteKey(key.id) }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize()
            }
        .contextMenu { Button("Edit…") { model.editing = .key(key.id) } }
        }
    }
}
