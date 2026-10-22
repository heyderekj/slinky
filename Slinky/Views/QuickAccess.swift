import AppKit
import SlinkyCoreShared
import SwiftUI

/// Layout C: the Palette. ⌥⌘K from anywhere. The selected item is always previewed,
/// so Return can't copy the wrong thing.
@MainActor
final class QuickAccess {
    static let shared = QuickAccess()
    private var panel: QuickAccessPanel?
    private weak var model: AppModel?

    func configure(_ model: AppModel) {
        self.model = model
        GlobalHotkey.shared.registerQuickAccess { [weak self] in self?.toggle() }
    }

    func toggle() {
        if let panel, panel.isVisible { close() } else { show() }
    }

    func show() {
        guard let model else { return }
        let panel = self.panel ?? makePanel(model)
        self.panel = panel
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - frame.height * 0.16))
        }
        model.quickAccessToken = UUID()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() { panel?.orderOut(nil) }

    private func makePanel(_ model: AppModel) -> QuickAccessPanel {
        let panel = QuickAccessPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 430),
                                     styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                                     backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        let host = NSHostingView(rootView: QuickAccessView().symbolVariant(.fill).environment(model))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }
}

final class QuickAccessPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }
}

struct QuickItem: Identifiable, Hashable {
    enum Kind: Hashable { case variable(project: UUID, env: AppEnvironment), key, kept, codes(UUID) }
    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let value: String
    let provider: String?
    let isLive: Bool
    let mono: Bool
    var icon: IconSubject
}

extension AppModel {
    var quickItems: [QuickItem] {
        if let cached = quickItemsCache { return cached }
        let items = buildQuickItems()
        quickItemsCache = items
        return items
    }

    private func buildQuickItems() -> [QuickItem] {
        var items: [QuickItem] = []
        for key in document.keys {
            items.append(QuickItem(id: key.id.uuidString, kind: .key, title: key.name, subtitle: key.provider ?? "Key",
                                   value: key.value, provider: key.provider, isLive: key.isLive, mono: true, icon: key.iconSubject))
        }
        for project in document.projects {
            for variable in project.variables {
                for env in AppEnvironment.allCases {
                    guard let value = variable.value(in: env) else { continue }
                    items.append(QuickItem(id: "\(variable.id)-\(env.rawValue)", kind: .variable(project: project.id, env: env),
                                           title: variable.name, subtitle: "\(project.name) · \(env.title)",
                                           value: value, provider: variable.provider,
                                           isLive: Detector.detect(value)?.isLive ?? false, mono: true,
                                           icon: variable.iconSubject))
                }
            }
        }
        for item in document.kept {
            items.append(QuickItem(id: item.id.uuidString, kind: .kept, title: item.label, subtitle: item.from.map { "\(item.kind.title) · \($0)" } ?? item.kind.title,
                                   value: item.value, provider: item.from, isLive: false, mono: false, icon: item.iconSubject))
        }
        for set in document.codeSets {
            guard let next = set.nextUnused else { continue }
            items.append(QuickItem(id: set.id.uuidString, kind: .codes(set.id), title: "\(set.account) recovery codes",
                                   subtitle: "\(set.remaining) left · copies the next unused code",
                                   value: set.codes[next], provider: set.account, isLive: false, mono: false, icon: set.iconSubject))
        }
        return items
    }
}

struct QuickAccessView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    private var results: [QuickItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = model.quickItems
        guard !q.isEmpty else { return Array(all.prefix(40)) }
        return all.filter { "\($0.title) \($0.subtitle)".lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.isUnlocked { unlocked } else { locked }
        }
        .frame(width: 720, height: 430)
        .glass(in: .rect(cornerRadius: 26))
        .onChange(of: model.quickAccessToken) { query = ""; selected = 0; focused = true }
        .onAppear { focused = true }
        .onKeyPress(.escape) { QuickAccess.shared.close(); return .handled }
    }

    private var locked: some View {
        VStack(spacing: 14) {
            KeyholeMark(size: 64)
            Text("Slinky is locked").font(.title3.weight(.semibold))
            Button { model.unlock() } label: { Label(model.unlockLabel, systemImage: "touchid") }
                .glassProminentButton()
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            if let error = model.errorMessage { Text(error).font(.callout).foregroundStyle(.red) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unlocked: some View {
        let items = results
        let current = items.indices.contains(selected) ? items[selected] : nil
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(.secondary)
                TextField("Search keys, codes and variables", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($focused)
                    .onChange(of: query) { selected = 0 }
                    .onKeyPress(.downArrow) { selected = min(items.count - 1, selected + 1); return .handled }
                    .onKeyPress(.upArrow) { selected = max(0, selected - 1); return .handled }
                    .onKeyPress(.return, phases: .down) { press in
                        guard let current else { return .handled }
                        copy(current, asLine: press.modifiers.contains(.command))
                        return .handled
                    }
                Text("⌥⌘K").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            Divider().opacity(0.5)
            HStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                row(item, on: index == selected)
                                    .id(index)
                                    .onTapGesture { selected = index }
                                    .onTapGesture(count: 2) { copy(item, asLine: false) }
                            }
                            if items.isEmpty {
                                Text(model.document.isEmpty ? "No items yet." : "No matches.")
                                    .foregroundStyle(.secondary).padding(.top, 30)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: selected) { proxy.scrollTo(selected) }
                }
                .frame(width: 320)
                Divider().opacity(0.5)
                preview(current)
            }
            Divider().opacity(0.5)
            HStack(spacing: 18) {
                hint("↵", "Copy"); hint("⌘↵", "Copy KEY=value"); hint("↑↓", "Move")
                Spacer()
                hint("esc", "Close")
            }
            .font(.caption)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
    }

    private func row(_ item: QuickItem, on: Bool) -> some View {
        HStack(spacing: 10) {
            ServiceIcon(subject: item.icon, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: .semibold, design: item.mono ? .monospaced : .default))
                    .lineLimit(1)
                Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if item.isLive { Chip(text: "live", style: .live) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(on ? Color.accentColor.opacity(0.18) : .clear, in: .rect(cornerRadius: 10))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func preview(_ item: QuickItem?) -> some View {
        if let item {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ServiceIcon(subject: item.icon, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.system(size: 15, weight: .semibold, design: item.mono ? .monospaced : .default))
                            .lineLimit(2).truncationMode(.middle)
                        Text(item.subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Text(Peek.of(item.value))
                    .font(.system(size: 14, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.paper, in: .rect(cornerRadius: 11))
                if item.isLive {
                    Label("This is a live key.", systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red)
                }
                Spacer()
                Label {
                    Text("**Return copies this item.** ") + Text(isCodes(item) ? "The next unused code is copied and marked as used." : AppModel.clipboardNote)
                } icon: { Image(systemName: "checkmark.circle") }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(spacing: 10) {
                Text("No items yet").font(.headline)
                Button("Add Item…") {
                    QuickAccess.shared.close()
                    model.openMainWindow?()
                    model.openAddItem()
                }
                .glassButton()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Text(key).fontWeight(.semibold)
            Text(text).foregroundStyle(.secondary)
        }
    }

    private func isCodes(_ item: QuickItem) -> Bool {
        if case .codes = item.kind { return true }
        return false
    }

    private func copy(_ item: QuickItem, asLine: Bool) {
        if case let .codes(setID) = item.kind, let index = model.document.codeSets.first(where: { $0.id == setID })?.nextUnused {
            model.useCode(index, in: setID)
        } else if asLine {
            model.copy("\(item.title)=\(item.value)", label: "\(item.title)=…")
        } else {
            model.copy(item.value, label: item.title)
        }
        QuickAccess.shared.close()
    }
}
