import SlinkyCoreShared
import SwiftUI

/// Layout B: the Shelf. Cards shaped like what they hold.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    let filter: LibraryFilter

    private let columns = [GridItem(.adaptive(minimum: 270, maximum: 420), spacing: 14, alignment: .top)]

    var body: some View {
        Group {
            if isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        switch filter {
                        case .codes: ForEach(model.document.codeSets) { CodeSetCard(set: $0) }
                        case .kept: ForEach(model.document.kept) { KeptCard(item: $0) }
                        case .keys: ForEach(model.document.keys) { KeyCard(key: $0) }
                        }
                    }
                    .padding(18)
                }
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
        .navigationTitle(filter.title)
        .navigationSubtitle(subtitle)
    }

    private var isEmpty: Bool {
        switch filter {
        case .codes: model.document.codeSets.isEmpty
        case .kept: model.document.kept.isEmpty
        case .keys: model.document.keys.isEmpty
        }
    }

    private var subtitle: String {
        switch filter {
        case .codes:
            let low = model.document.codeSets.filter(\.isLow).count
            return "\(model.document.codeSets.count) accounts" + (low > 0 ? " · \(low) running low" : "")
        case .kept: return "Things a site told you to keep safe"
        case .keys: return "Personal tokens and keys that aren't tied to one project"
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            KeyholeMark(size: 72)
            Text("Nothing to hide. Yet.").font(.title2.weight(.bold))
            Text(emptyLine).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 400)
            Button {
                model.tuckPrefill = ""
                model.tuckProject = nil
                model.showTuck = true
            } label: {
                Label("Tuck It Away", systemImage: "plus")
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyLine: String {
        switch filter {
        case .codes: "Paste the block of recovery codes a site gave you. Click one to copy it, and Slinky crosses it off."
        case .kept: "Recovery keys, setup keys, the router password. Anything a site said to store somewhere safe."
        case .keys: "Personal tokens and API keys you use across projects."
        }
    }
}

private struct CardChrome<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
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
                Label("\(set.remaining) codes left. Time for fresh ones.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(Array(set.codes.enumerated()), id: \.offset) { index, code in
                    let used = set.used.contains(index)
                    Button {
                        model.useCode(index, in: set.id)
                    } label: {
                        Text(code)
                            .font(.system(size: 12, design: .monospaced))
                            .strikethrough(used)
                            .foregroundStyle(used ? Color.secondary.opacity(0.6) : Color.primary)
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
                    Text("Saved \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Menu {
                    Button("Remove", role: .destructive) { model.deleteCodeSet(set.id) }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize()
            }
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
                Button { model.copy(item.value, label: item.label) } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .buttonStyle(.glass).controlSize(.small)
                if item.kind == .recoveryKey {
                    if item.printedCopy {
                        Label("Printed copy", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Print a Copy…") {
                            RecoveryPrinter.print(item.value)
                            model.markPrinted(item.id)
                        }
                        .buttonStyle(.glass).controlSize(.small)
                    }
                }
                Spacer()
                Menu {
                    Button("Remove", role: .destructive) { model.deleteKept(item.id) }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize()
            }
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
                    Text("KEY").font(.system(size: 9.5, weight: .bold)).tracking(0.5).foregroundStyle(.tertiary)
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
                Button { model.copy(key.value, label: key.name) } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .buttonStyle(.glass).controlSize(.small)
                Menu {
                    Button("Remove", role: .destructive) { model.deleteKey(key.id) }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize()
            }
        }
    }
}
