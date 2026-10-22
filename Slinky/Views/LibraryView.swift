import SlinkyCoreShared
import SwiftUI

/// Layout B: the library. A compact list (one line per item, Copy always in reach) with the details on the right.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    let filter: LibraryFilter
    /// The All Items heading follows the animation: what Slinky does with each example, then the tagline.
    @State private var playing: Int?
    // Only whether the pane is open, and the sort. Nothing about any item.
    @AppStorage("libraryInspector") private var showInspector = true
    @AppStorage("librarySort") private var sort: LibrarySort = .added
    /// Not remembered: a filter left on would make items seem to vanish next time.
    @State private var show: LibraryShow = .all

    var body: some View {
        @Bindable var model = model
        Group {
            if isEmpty {
                empty
            } else if nothingMatches {
                noMatches
            } else {
                list
            }
        }
        .screenTitle(filter.title, subtitle: subtitle)
        // A filter belongs to the view it was picked in.
        .onChange(of: filter) { show = .all }
        .toolbar {
            // Away while Slinky locks or unlocks, when the toolbar is the locked window's.
            if !isEmpty, !model.lockedChrome {
                ToolbarItem { sortAndFilter }
                ToolbarItem {
                    Button { showInspector.toggle() } label: { Label("Details", systemImage: "sidebar.right") }
                        .help(showInspector ? "Hide details" : "Show details")
                }
            }
        }
        .detailsPane(isPresented: Binding(get: { showInspector && !isEmpty }, set: { showInspector = $0 })) {
            Group {
                if let ref = visibleSelection {
                    ItemDetail(ref: ref).id(ref)
                } else {
                    // Quiet: this sits in a narrow sidebar.
                    VStack(spacing: 8) {
                        Image(systemName: "sidebar.right").font(.system(size: 22)).foregroundStyle(.tertiary)
                        Text("Select an item to see its details.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var showKeys: Bool { filter != .recovery && !keys.isEmpty }
    private var showCodes: Bool { filter != .keys && !codeSets.isEmpty }
    private var showKept: Bool { filter != .keys && !kept.isEmpty }
    private var showFiles: Bool { filter != .recovery && !files.isEmpty }

    // MARK: Sort and filter

    /// The items to list, filtered by `show` and in `sort` order.
    private var keys: [Key] {
        let soon = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
        let shown = model.document.keys.filter { key in
            switch show {
            case .all: true
            case .live: key.isLive
            case .expiring: key.expires.map { $0 < soon } ?? false
            case .low: false
            }
        }
        return shown.sorted { a, b in
            switch sort {
            case .added: return a.created > b.created
            case .name: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .service: return ordered(serviceName(a.iconSubject), a.name, serviceName(b.iconSubject), b.name)
            case .expiry:
                switch (a.expires, b.expires) {
                case let (x?, y?): return x < y
                case (.some, nil): return true
                case (nil, .some): return false
                case (nil, nil): return a.name.localizedStandardCompare(b.name) == .orderedAscending
                }
            }
        }
    }

    private var codeSets: [CodeSet] {
        let shown = model.document.codeSets.filter { set in
            switch show {
            case .all: true
            case .low: set.isLow
            case .live, .expiring: false
            }
        }
        return shown.sorted { a, b in
            switch sort {
            case .added: return a.created > b.created
            case .name: return a.account.localizedStandardCompare(b.account) == .orderedAscending
            case .service: return ordered(serviceName(a.iconSubject), a.account, serviceName(b.iconSubject), b.account)
            // The nearest to running out first.
            case .expiry: return a.remaining < b.remaining
            }
        }
    }

    private var kept: [KeptItem] {
        guard show == .all else { return [] }
        return model.document.kept.sorted { a, b in
            switch sort {
            case .added: return a.created > b.created
            case .name, .expiry: return a.label.localizedStandardCompare(b.label) == .orderedAscending
            case .service: return ordered(serviceName(a.iconSubject), a.label, serviceName(b.iconSubject), b.label)
            }
        }
    }

    private func serviceName(_ subject: IconSubject) -> String? { IconResolver.shared.service(for: subject)?.name }

    /// By service (items Slinky can't place go last), then by name.
    private func ordered(_ s1: String?, _ n1: String, _ s2: String?, _ n2: String) -> Bool {
        switch (s1, s2) {
        case let (x?, y?) where x != y: return x.localizedStandardCompare(y) == .orderedAscending
        case (.some, nil): return true
        case (nil, .some): return false
        default: return n1.localizedStandardCompare(n2) == .orderedAscending
        }
    }

    private var nothingMatches: Bool { !showKeys && !showCodes && !showKept && !showFiles }

    private var files: [SecretFile] {
        guard show == .all else { return [] }
        return model.document.secretFiles.sorted { a, b in
            switch sort {
            case .added: return a.created > b.created
            default: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
    }

    private var sortAndFilter: some View {
        Menu {
            Picker("Sort By", selection: $sort) {
                ForEach(LibrarySort.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            Picker("Show", selection: $show) {
                ForEach(LibraryShow.allCases(for: filter), id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort and Filter", systemImage: show == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
        }
        .help(show == .all ? "Sort and filter" : "Showing \(show.title.lowercased())")
    }

    private var noMatches: some View {
        VStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 30)).foregroundStyle(.tertiary)
            Text("Nothing here is \(show.matchPhrase)").font(.title3.weight(.semibold))
            Button("Show Everything") { show = .all }
                .glassButton()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The selection, if it's in this view (another view's pick stays put but isn't shown here).
    private var visibleSelection: LibraryRef? {
        switch model.librarySelection {
        case let .key(id)? where showKeys: model.document.keys.contains { $0.id == id } ? .key(id) : nil
        case let .codes(id)? where showCodes: model.document.codeSets.contains { $0.id == id } ? .codes(id) : nil
        case let .kept(id)? where showKept: model.document.kept.contains { $0.id == id } ? .kept(id) : nil
        case let .file(id)? where showFiles: model.document.secretFiles.contains { $0.id == id } ? .file(id) : nil
        default: nil
        }
    }

    private var list: some View {
        @Bindable var model = model
        return List(selection: $model.librarySelection) {
            if showKeys {
                Section {
                    if filter == .all { groupTitle("Keys & Tokens") }
                    ForEach(keys) { KeyRow(key: $0).tag(LibraryRef.key($0.id)) }
                }
            }
            if showCodes {
                Section {
                    groupTitle("Recovery Codes")
                    ForEach(codeSets) { CodeSetRow(set: $0).tag(LibraryRef.codes($0.id)) }
                }
            }
            if showFiles {
                Section {
                    groupTitle("Files")
                    ForEach(files) { FileRow(file: $0).tag(LibraryRef.file($0.id)) }
                }
            }
            if showKept {
                Section {
                    groupTitle("Recovery Keys")
                    ForEach(kept) { KeptRow(item: $0).tag(LibraryRef.kept($0.id)) }
                }
            }
        }
        // Group titles are plain rows, not section headers: on the Mac a section header draws a line under itself
        // that ran on under the left sidebar but stopped with the rows on the right.
        .listStyle(.inset)
        .contextMenu(forSelectionType: LibraryRef.self) { refs in
            if refs.count == 1, let ref = refs.first {
                ItemActions(ref: ref)
            } else if !refs.isEmpty {
                Button("Delete \(refs.count) Items", role: .destructive) { refs.forEach(delete) }
            }
        } primaryAction: { refs in
            // Double-click opens the full Edit panel. A single click already shows the details on the right.
            if refs.count == 1, let ref = refs.first { model.editing = ref.editTarget }
        }
        // Selecting an item opens the details on the right, even if they were closed.
        .onChange(of: model.librarySelection) { _, selection in
            if selection != nil, !showInspector { showInspector = true }
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

    /// A group's title inside the list: not selectable, no line under it.
    private func groupTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
            .selectionDisabled()
            .listRowSeparator(.hidden)
            .accessibilityAddTraits(.isHeader)
    }

    private func copy(_ ref: LibraryRef) { ItemActions.copy(ref, model: model) }

    private func delete(_ ref: LibraryRef) {
        switch ref {
        case let .key(id): model.deleteKey(id)
        case let .codes(id): model.deleteCodeSet(id)
        case let .kept(id): model.deleteKept(id)
        case let .file(id): model.deleteFile(id)
        }
        if model.librarySelection == ref { model.librarySelection = nil }
    }

    private var isEmpty: Bool {
        switch filter {
        case .all: model.document.keys.isEmpty && model.document.codeSets.isEmpty && model.document.kept.isEmpty && model.document.secretFiles.isEmpty
        case .keys: model.document.keys.isEmpty && model.document.secretFiles.isEmpty
        case .recovery: model.document.codeSets.isEmpty && model.document.kept.isEmpty
        }
    }

    /// Short on purpose: macOS keeps the toolbar's title and subtitle on one line, and a long subtitle pushes
    /// the content column wide enough to squeeze the sidebar below its minimum. Counts, not descriptions
    /// (the empty states say what each view is for).
    private var subtitle: String {
        let doc = model.document
        func count(_ n: Int, _ one: String, _ many: String) -> String { counted(n, one, many) }
        if show != .all {
            let n = keys.count + codeSets.count + kept.count + (showFiles ? files.count : 0)
            return show == .live ? counted(n, "live key") : "\(n.formatted()) \(show.title.lowercased())"
        }
        switch filter {
        case .all:
            return count(doc.keys.count + doc.codeSets.count + doc.kept.count + doc.secretFiles.count, "item", "items")
        case .keys:
            return count(doc.keys.count + doc.secretFiles.count, "item", "items")
        case .recovery:
            let low = doc.codeSets.filter(\.isLow).count
            return count(doc.codeSets.count + doc.kept.count, "item", "items") + (low > 0 ? " · \(low) running low" : "")
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


enum LibrarySort: String, CaseIterable {
    case added, name, service, expiry

    var title: String {
        switch self {
        case .added: "Date Added"
        case .name: "Name"
        case .service: "Service"
        case .expiry: "Expiry"
        }
    }
}

/// Quick filters, each for something a person acts on.
enum LibraryShow: String, CaseIterable {
    case all, live, expiring, low

    var title: String {
        switch self {
        case .all: "Everything"
        case .live: "Live Keys"
        case .expiring: "Expiring Soon"
        case .low: "Running Low"
        }
    }

    /// "Nothing here is …"
    var matchPhrase: String {
        switch self {
        case .all: "here"
        case .live: "a live key."
        case .expiring: "expiring in the next 30 days."
        case .low: "running low."
        }
    }

    /// Only the filters that make sense in this view.
    static func allCases(for filter: LibraryFilter) -> [LibraryShow] {
        switch filter {
        case .all: allCases
        case .keys: [.all, .live, .expiring]
        case .recovery: [.all, .low]
        }
    }
}
