import SlinkyCoreShared
import SwiftUI

/// Layout B: the library. A compact list (one line per item, Copy always in reach) with the details on the right.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    let filter: LibraryFilter
    /// The All Items heading follows the animation: what Slinky does with each example, then the tagline.
    @State private var playing: Int?
    // Only whether the pane is open. Nothing about any item.
    @AppStorage("libraryInspector") private var showInspector = true

    var body: some View {
        @Bindable var model = model
        Group {
            if isEmpty {
                empty
            } else {
                list
            }
        }
        .screenTitle(filter.title, subtitle: subtitle)
        .toolbar {
            // Away while Slinky locks or unlocks, when the toolbar is the locked window's.
            if !isEmpty, !model.lockedChrome {
                ToolbarItem {
                    Button { showInspector.toggle() } label: { Label("Details", systemImage: "sidebar.right") }
                        .help(showInspector ? "Hide details" : "Show details")
                }
            }
        }
        .detailsPane(isPresented: showInspector && !isEmpty) {
            Group {
                if let ref = visibleSelection {
                    ItemDetail(ref: ref).id(ref)
                } else {
                    ContentUnavailableView("No Item Selected", systemImage: "sidebar.right",
                                           description: Text("Pick an item to see its details."))
                }
            }
        }
    }

    private var showKeys: Bool { filter != .recovery && !model.document.keys.isEmpty }
    private var showCodes: Bool { filter != .keys && !model.document.codeSets.isEmpty }
    private var showKept: Bool { filter != .keys && !model.document.kept.isEmpty }

    /// The selection, if it's in this view (another view's pick stays put but isn't shown here).
    private var visibleSelection: LibraryRef? {
        switch model.librarySelection {
        case let .key(id)? where showKeys: model.document.keys.contains { $0.id == id } ? .key(id) : nil
        case let .codes(id)? where showCodes: model.document.codeSets.contains { $0.id == id } ? .codes(id) : nil
        case let .kept(id)? where showKept: model.document.kept.contains { $0.id == id } ? .kept(id) : nil
        default: nil
        }
    }

    private var list: some View {
        @Bindable var model = model
        return List(selection: $model.librarySelection) {
            if showKeys {
                Section {
                    ForEach(model.document.keys) { KeyRow(key: $0).tag(LibraryRef.key($0.id)) }
                } header: {
                    if filter == .all { Text("Keys & Tokens") }
                }
            }
            if showCodes {
                Section("Recovery Codes") {
                    ForEach(model.document.codeSets) { CodeSetRow(set: $0).tag(LibraryRef.codes($0.id)) }
                }
            }
            if showKept {
                Section("Recovery Keys") {
                    ForEach(model.document.kept) { KeptRow(item: $0).tag(LibraryRef.kept($0.id)) }
                }
            }
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: LibraryRef.self) { refs in
            if refs.count == 1, let ref = refs.first {
                ItemActions(ref: ref)
            } else if !refs.isEmpty {
                Button("Delete \(refs.count) Items", role: .destructive) { refs.forEach(delete) }
            }
        } primaryAction: { refs in
            // Double-click edits.
            if refs.count == 1, let ref = refs.first { model.editing = ref.editTarget }
        }
        // ⌘C (and Edit › Copy) copies the selected item. Return opens the details; Delete moves it to Recently Deleted.
        .onCommand(#selector(NSText.copy(_:))) { visibleSelection.map(copy) }
        .onDeleteCommand { visibleSelection.map(delete) }
        .onKeyPress(.return) {
            guard visibleSelection != nil else { return .ignored }
            showInspector = true
            return .handled
        }
    }

    private func copy(_ ref: LibraryRef) { ItemActions.copy(ref, model: model) }

    private func delete(_ ref: LibraryRef) {
        switch ref {
        case let .key(id): model.deleteKey(id)
        case let .codes(id): model.deleteCodeSet(id)
        case let .kept(id): model.deleteKept(id)
        }
        if model.librarySelection == ref { model.librarySelection = nil }
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
                model.openAddItem()
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

