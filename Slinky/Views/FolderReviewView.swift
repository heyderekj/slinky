import SlinkyCoreShared
import SwiftUI

/// New Project and Update from Folder: one panel that floats like Add Item, over a soft dim.
struct FolderReviewOverlay: View {
    @Environment(AppModel.self) private var model
    let review: FolderReview

    var body: some View {
        ZStack {
            PanelBackdrop(close: close)
            FolderReviewPanel(review: review, close: close)
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { model.review = nil }
    }
}

/// Reads the folder (or one .env file) and shows, environment by environment, what would change: new names,
/// changed values, the same values, and names only Slinky has. Names and peeks only, never whole values.
/// Nothing is saved, and nothing in the folder changes, until the button at the bottom.
struct FolderReviewPanel: View {
    @Environment(AppModel.self) private var model
    let review: FolderReview
    let close: () -> Void

    @State private var name = ""
    @State private var nameTouched = false
    /// Folders (or the one file) being read. Starts from the review; New Project can change it.
    @State private var folders: [URL] = []
    @State private var scans: [ProjectScan] = []
    @State private var reading = false
    /// Included env files and their environments, by `key(scan, file)`.
    @State private var include: Set<String> = []
    @State private var environments: [String: AppEnvironment] = [:]
    @State private var picks = FolderChanges.Picks()
    @State private var keyFiles: Set<String> = []
    @State private var expanded: Set<AppEnvironment> = []
    @State private var trashAfter = true
    @State private var dropTargeted = false
    @State private var appeared = false
    @FocusState private var nameFocused: Bool

    private var isNew: Bool { review.target == .newProject }

    private var project: Project {
        if case let .project(id) = review.target, let p = model.document.projects.first(where: { $0.id == id }) { return p }
        return Project(name: name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(isNew ? "New Project" : "Update from Folder").font(.headline)
                Spacer()
                PanelCloseButton(action: close)
            }
            .padding(.bottom, 12)

            header
            if reading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading the folder…").font(.callout).foregroundStyle(.secondary)
                }
                .padding(.top, 14)
            } else if !scans.isEmpty {
                ScrollView {
                    found.padding(.vertical, 2)
                }
                .frame(maxHeight: 360)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            }
            if review.trashAfter != nil {
                Toggle("Then move \(review.trashAfter?.lastPathComponent ?? ".env") to the Trash, and write a .env.example with the names if there isn't one.",
                       isOn: $trashAfter)
                    .toggleStyle(.checkbox)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
            }
            footer.padding(.top, 14)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 720)
        .glass(in: .rect(cornerRadius: 28))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 14)
        .panelEntrance(appeared)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard isNew else { return false }
            Task {
                let urls = await AppModel.urls(from: providers)
                guard let url = urls.first else { return }
                var isDir: ObjCBool = false
                let isFolder = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
                read(folders: [isFolder ? url : url.deletingLastPathComponent()])
            }
            return true
        }
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) { appeared = true }
            if let scans = review.scans {
                use(scans)
            } else if let file = review.file {
                read(file: file)
            } else if !review.folders.isEmpty {
                read(folders: review.folders)
            } else {
                Task { nameFocused = true }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Monogram(text: isNew ? name : project.name, size: 42)
                if isNew {
                    TextField("Project name", text: Binding(get: { name }, set: { name = $0; nameTouched = true }),
                              prompt: Text("Project name, like Slinky"))
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .limit($name, to: FieldLimit.name)
                        .font(.title2.weight(.semibold))
                        .focused($nameFocused)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.name).font(.title2.weight(.semibold)).lineLimit(1)
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            if !folders.isEmpty || review.file != nil {
                ForEach(places, id: \.self) { place in
                    HStack(spacing: 10) {
                        Image(systemName: review.file == nil ? "folder" : "doc.text").foregroundStyle(.tint)
                        Text(place)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        if scans.contains(where: \.isGitRepo) && place == places.first { Chip(text: "git", style: .plain) }
                        Spacer(minLength: 8)
                        if isNew, place == places.first {
                            Button("Change…", action: chooseFolder).buttonStyle(.borderless)
                            IconButton(symbol: "xmark", help: "Don't link a folder") { unlink() }
                        }
                    }
                }
            } else if isNew {
                dropZone
            }
        }
        .padding(16)
        .background(Color.paper, in: .rect(cornerRadius: 18))
    }

    private var subtitle: String {
        if review.file != nil { return "Reading one file" }
        let linked = Set(project.folders)
        let adding = folders.filter { !linked.contains($0.path) }
        return adding.isEmpty ? "Reading its linked \(folders.count == 1 ? "folder" : "folders")" : "Linking a folder"
    }

    private var places: [String] {
        if let file = review.file { return [(file.path as NSString).abbreviatingWithTildeInPath] }
        return folders.map { ($0.path as NSString).abbreviatingWithTildeInPath }
    }

    private var dropZone: some View {
        HStack(spacing: 14) {
            Image(systemName: "folder.badge.plus")
                .font(.title2.weight(.medium))
                .foregroundStyle(.tint)
                .frame(width: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text("Drop the project folder here").font(.callout.weight(.semibold))
                Text("Slinky reads its .env files, including apps inside it, and shows what it found. It never changes them.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Choose Folder…", action: chooseFolder)
                .glassButton()
        }
        .padding(14)
        .background(dropTargeted ? Color.accentColor.opacity(0.12) : Color.clear, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                          style: StrokeStyle(lineWidth: dropTargeted ? 1.5 : 1, dash: [4, 3])))
        .animation(.smooth(duration: 0.2), value: dropTargeted)
    }

    // MARK: What was found

    @ViewBuilder
    private var found: some View {
        let changes = self.changes
        VStack(alignment: .leading, spacing: 16) {
            if allFiles.isEmpty && allExamples.isEmpty {
                Text(isNew ? "No .env files here. You can add variables after creating the project, by pasting them or dropping a .env file."
                           : "No .env files here.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                filesSection
            }
            if !changes.changes.isEmpty {
                FolderReviewChanges(changes: changes, picks: $picks, expanded: $expanded, isNew: isNew)
            }
            if !allKeyFiles.isEmpty { keyFilesSection }
            notes(changes)
        }
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Files").font(.headline).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(groups, id: \.self) { group in
                    if groups.count > 1 {
                        Text(group.isEmpty ? "Project folder" : group)
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 2)
                    }
                    ForEach(files(in: group), id: \.key) { item in
                        fileRow(item.scan, item.file)
                    }
                    ForEach(examples(in: group), id: \.id) { example in
                        exampleRow(example)
                    }
                }
                if !skipped.isEmpty {
                    Text("Skipped \(skipped.joined(separator: " and ")). They hold encrypted values or keys for other tools.")
                        .font(.subheadline).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                }
            }
            .card(cornerRadius: 14)
        }
    }

    private func fileRow(_ scan: ProjectScan, _ file: ProjectScan.EnvFile) -> some View {
        let key = Self.key(scan, file)
        let on = include.contains(key)
        return HStack(spacing: 12) {
            Toggle(file.fileName, isOn: Binding(get: { on }, set: { setIncluded(key, $0) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(file.fileName).font(.body.monospaced().weight(.semibold))
                    if file.ignoredByGit == false { Chip(text: "Not in .gitignore", style: .warn) }
                }
                Text(caption(for: file, key: key)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Menu {
                ForEach(AppEnvironment.allCases) { e in
                    Button(e.title) { environments[key] = e; resetPicks() }
                }
            } label: {
                ChipLabel(symbol: nil, text: environment(key, file).title, menu: true)
            }
            .menuStyle(.button)
            .buttonStyle(ChipButtonStyle(selected: on))
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(!on)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(on ? 1 : 0.55)
    }

    private func caption(for file: ProjectScan.EnvFile, key: String) -> String {
        guard !file.lines.isEmpty else { return "No variables" }
        let names = Set(file.names).count
        if isNew || !include.contains(key) {
            return "\(counted(names, "variable")) · " + file.names.uniqued().prefix(3).joined(separator: ", ") + (names > 3 ? "…" : "")
        }
        let rows = changes.changes.filter { $0.environment == environment(key, file) && $0.offers.contains { $0.source == sourceID(key) } }
        let new = rows.filter { $0.status() == .new }.count, changed = rows.filter { $0.status() == .changed }.count
        let parts = [(new, "new"), (changed, "changed")].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
        return parts.isEmpty ? "\(counted(names, "variable")), all the same as in Slinky" : parts.joined(separator: ", ")
    }

    private func exampleRow(_ example: ProjectScan.Example) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle").foregroundStyle(.secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text((example.id as NSString).lastPathComponent).font(.body.monospaced().weight(.semibold))
                Text("\(counted(example.names.count, "name")). Slinky uses these to show which variables are missing.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var keyFilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Key files").font(.headline).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(allKeyFiles, id: \.id) { file in
                    let on = keyFiles.contains(file.id)
                    HStack(spacing: 12) {
                        Toggle(file.fileName, isOn: Binding(get: { on }, set: { if $0 { keyFiles.insert(file.id) } else { keyFiles.remove(file.id) } }))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(file.kind == .other ? file.fileName : file.kind.title).font(.body.weight(.semibold))
                                if alreadySaved(file) { Chip(text: "Already in Slinky", style: .plain) }
                                if file.likelyFixture { Chip(text: "Looks like a test file", style: .plain) }
                            }
                            Text(file.id).font(.subheadline.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .opacity(on ? 1 : 0.55)
                }
            }
            .card(cornerRadius: 14)
            Text("Checked files are saved to Keys & Tokens. The originals stay in the folder.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func notes(_ changes: FolderChanges) -> some View {
        let notIgnored = allFiles.contains { include.contains($0.key) && $0.file.ignoredByGit == false }
        VStack(alignment: .leading, spacing: 6) {
            if notIgnored {
                Label("Some of these files aren't in .gitignore, so git could commit them. Slinky won't change your files; add them to .gitignore to keep them out of git.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.attention)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !changes.expected.isEmpty {
                let missing = stillMissing(changes)
                Label(missing.isEmpty ? "Everything the example files list is covered."
                                      : "Still missing after this: " + missing.prefix(5).joined(separator: ", ") + (missing.count > 5 ? " and \(missing.count - 5) more" : ""),
                      systemImage: missing.isEmpty ? "checkmark.circle" : "circle.dashed")
                    .foregroundStyle(missing.isEmpty ? Color.done : Color.secondary)
            }
            if !isNew, !changes.expectedRemoved.isEmpty, replacesExpected {
                Label("No longer in the example files: " + changes.expectedRemoved.prefix(5).joined(separator: ", "), systemImage: "minus.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            EncryptedNote()
            Spacer()
            Button("Cancel", action: close)
                .keyboardShortcut(.cancelAction)
                .glassButton()
            Button(action: apply) {
                HStack(spacing: 8) {
                    Text(buttonTitle)
                    Text("↵").font(.callout.weight(.semibold)).opacity(0.6).accessibilityHidden(true)
                }
            }
            .lineLimit(1)
            .fixedSize()
            .keyboardShortcut(.defaultAction)
            .glassProminentButton()
            .disabled(isNew && trimmedName.isEmpty || reading)
        }
        .dialogButtons()
    }

    private var buttonTitle: String {
        let summary = changes.summary(for: picks)
        let n = summary.new + summary.updated
        let files = chosenKeyFiles.count
        if isNew { return n == 0 ? "Create Project" : "Create and Import \(counted(n, "Variable"))" }
        let linking = !folders.filter { !project.folders.contains($0.path) }.isEmpty
        if n > 0 { return (linking ? "Link and Update " : "Update ") + counted(n, "Variable") }
        if files > 0 { return "Save \(counted(files, "Key File"))" }
        return linking ? "Link Folder" : "Done"
    }

    // MARK: Behavior

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private static func key(_ scan: ProjectScan, _ file: ProjectScan.EnvFile) -> String { scan.folder.path + "|" + file.id }

    /// How a file is named in the review: its path inside the folder, with the folder's name when there are several.
    private func sourceID(_ key: String) -> String {
        guard let bar = key.firstIndex(of: "|") else { return key }
        let path = String(key[key.index(after: bar)...])
        return scans.count > 1 ? (String(key[..<bar]) as NSString).lastPathComponent + "/" + path : path
    }

    private var allFiles: [(key: String, scan: ProjectScan, file: ProjectScan.EnvFile)] {
        scans.flatMap { scan in scan.envFiles.map { (Self.key(scan, $0), scan, $0) } }
    }

    private var allExamples: [ProjectScan.Example] { scans.flatMap(\.examples) }
    private var allKeyFiles: [ProjectScan.FoundFile] { scans.flatMap(\.secretFiles) }
    private var skipped: [String] { scans.flatMap(\.skippedFiles).map { ($0 as NSString).lastPathComponent }.uniqued() }
    private var chosenKeyFiles: [ProjectScan.FoundFile] { allKeyFiles.filter { keyFiles.contains($0.id) } }

    /// Subfolders with .env or example files (key files are listed on their own).
    private var groups: [String] {
        scans.flatMap(\.groups).uniqued().filter { g in !files(in: g).isEmpty || !examples(in: g).isEmpty }
    }
    private func files(in group: String) -> [(key: String, scan: ProjectScan, file: ProjectScan.EnvFile)] {
        allFiles.filter { $0.file.folder == group }
    }
    private func examples(in group: String) -> [ProjectScan.Example] {
        allExamples.filter { ProjectScanFolder.of($0.id) == group }
    }

    private func environment(_ key: String, _ file: ProjectScan.EnvFile) -> AppEnvironment {
        if let chosen = environments[key] { return chosen }
        if review.file != nil, ProjectScan.environmentHint(for: file.fileName) == nil, let hint = review.environmentHint { return hint }
        return file.environment
    }

    private var sources: [FolderChanges.Source] {
        allFiles.filter { include.contains($0.key) }.map {
            FolderChanges.Source(id: sourceID($0.key), environment: environment($0.key, $0.file), lines: $0.file.lines,
                                 precedence: ProjectScan.precedence(of: $0.file.fileName))
        }
    }

    /// Names the example files list: from these folders plus the project's other linked folders.
    private var expected: [String] {
        var names = scans.flatMap(\.expected)
        if !isNew {
            let others = project.folders.filter { path in !folders.contains { $0.path == path } }.map { URL(fileURLWithPath: $0) }
            names += ProjectScan.expectedNames(inFolders: others)
        }
        return names.uniqued()
    }

    /// Folders with example files replace the expected list; one .env file only adds.
    private var replacesExpected: Bool { review.file == nil && !allExamples.isEmpty }

    private var changes: FolderChanges {
        FolderChanges.compare(project, with: sources, expected: expected)
    }

    private func stillMissing(_ changes: FolderChanges) -> [String] {
        var have = Set(project.variables.map(\.name))
        for c in changes.changes where picks.rows.contains(c.id) { have.insert(c.name) }
        return changes.expected.filter { !have.contains($0) }
    }

    private func alreadySaved(_ file: ProjectScan.FoundFile) -> Bool {
        model.document.secretFiles.contains { $0.data == file.data }
    }

    private func setIncluded(_ key: String, _ on: Bool) {
        if on { include.insert(key) } else { include.remove(key) }
        resetPicks()
    }

    /// New and changed rows start checked (not a change to an empty value). Sections start open in an update.
    private func resetPicks() {
        let changes = self.changes
        picks = changes.defaultPicks
        if !isNew { expanded = Set(changes.changes.map(\.environment)) }
    }

    private func read(folders: [URL]) {
        self.folders = folders
        reading = true
        Task {
            let scans = await Task.detached(priority: .userInitiated) {
                folders.map { ProjectScan.scan($0, depth: 3, secretFiles: true) }
            }.value
            use(scans)
        }
    }

    private func read(file: URL) {
        reading = true
        Task {
            let scan = await Task.detached(priority: .userInitiated) { ProjectScan.scan(file: file) }.value
            use([scan])
        }
    }

    private func use(_ scans: [ProjectScan]) {
        self.scans = scans
        reading = false
        if folders.isEmpty, review.file == nil { folders = scans.map(\.folder) }
        // Files with variables start included, except ones that look like test fixtures in a subfolder.
        include = Set(allFiles.filter { !$0.file.lines.isEmpty && !($0.file.folder != "" && ProjectScan.isLikelyFixture($0.file.id)) }.map(\.key))
        environments = [:]
        keyFiles = Set(allKeyFiles.filter { !$0.likelyFixture && !alreadySaved($0) }.map(\.id))
        if isNew, !nameTouched || trimmedName.isEmpty, let first = scans.first {
            name = first.suggestedName
            nameTouched = false
        }
        resetPicks()
    }

    private func unlink() {
        folders = []
        scans = []
        include = []
        environments = [:]
        keyFiles = []
        picks = FolderChanges.Picks()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"
        panel.message = "Choose the project folder. Slinky reads its .env files and never changes them."
        if panel.runModal() == .OK, let url = panel.url { read(folders: [url]) }
    }

    private func apply() {
        guard !(isNew && trimmedName.isEmpty) else { return }
        var review = self.review
        review.folders = self.review.file == nil ? folders : []
        model.applyReview(review, name: trimmedName, changes: changes, picks: picks, keyFiles: chosenKeyFiles,
                          replaceExpected: replacesExpected, trashAfter: trashAfter)
        close()
    }
}

/// The folder part of a path inside a scanned folder ("apps/web" for "apps/web/.env.example").
enum ProjectScanFolder {
    static func of(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }
}
