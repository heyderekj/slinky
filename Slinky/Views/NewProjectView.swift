import SlinkyCoreShared
import SwiftUI

/// New Project floats like Add Item, over a soft dim with the window blurred behind.
struct NewProjectOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.24))
                .ignoresSafeArea()
                .onTapGesture { close() }
                .accessibilityHidden(true)
            NewProjectPanel(close: close)
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { model.showNewProject = false }
        model.newProjectFolder = nil
    }
}

/// Name it, or hand Slinky the project folder: it reads every .env file (names only on screen),
/// guesses each file's environment, checks .gitignore, reads .env.example for what's missing,
/// and creates the project with everything imported in one step. It never changes the folder.
struct NewProjectPanel: View {
    @Environment(AppModel.self) private var model
    let close: () -> Void

    @State private var name = ""
    @State private var nameTouched = false
    @State private var scan: ProjectScan?
    @State private var include: Set<String> = []
    @State private var environments: [String: AppEnvironment] = [:]
    @State private var dropTargeted = false
    @State private var appeared = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("New Project").font(.headline)
                Spacer()
                Keycap("esc")
            }
            .padding(.bottom, 14)

            header
            if let scan {
                found(scan).padding(.top, 16)
            }
            footer.padding(.top, 18)
        }
        .padding(24)
        .frame(width: 720)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 14)
        .scaleEffect(appeared ? 1 : 0.95)
        .offset(y: appeared ? 0 : 14)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: scan?.folder)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        var isDir: ObjCBool = false
                        let isFolder = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
                        use(isFolder ? url : url.deletingLastPathComponent())
                    }
                }
            }
            return true
        }
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) { appeared = true }
            if let folder = model.newProjectFolder {
                use(folder)
            } else {
                Task { nameFocused = true }
            }
        }
    }

    // MARK: Name and folder

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Monogram(text: name.isEmpty ? "?" : name, size: 42)
                TextField("", text: Binding(get: { name }, set: { name = $0; nameTouched = true }),
                          prompt: Text("Project name, like harvous"))
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .semibold))
                    .focused($nameFocused)
            }

            if let scan {
                HStack(spacing: 10) {
                    Image(systemName: "folder.fill").foregroundStyle(.tint)
                    Text(scan.folder.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    if scan.isGitRepo {
                        Chip(text: "git", style: .plain)
                    }
                    Spacer(minLength: 8)
                    Button("Change…", action: chooseFolder)
                        .buttonStyle(.borderless)
                    IconButton(symbol: "xmark", help: "Don't link a folder") { unlink() }
                }
            } else {
                dropZone
            }
        }
        .padding(16)
        .background(Color.paper, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1))
    }

    private var dropZone: some View {
        HStack(spacing: 14) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text("Drop the project folder here").font(.callout.weight(.semibold))
                Text("Slinky reads its .env files to set up the project. It never changes them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Choose Folder…", action: chooseFolder)
                .buttonStyle(.glass)
        }
        .padding(14)
        .background(dropTargeted ? Color.accentColor.opacity(0.12) : Color.clear, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                          style: StrokeStyle(lineWidth: dropTargeted ? 1.5 : 1, dash: [4, 3])))
        .animation(.smooth(duration: 0.2), value: dropTargeted)
    }

    // MARK: What's in the folder

    @ViewBuilder
    private func found(_ scan: ProjectScan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(scan.envFiles.isEmpty ? "No .env files in this folder" : "Found in this folder")
                .font(.callout).foregroundStyle(.secondary)

            if scan.envFiles.isEmpty && scan.exampleFile == nil {
                Text("You can add variables after creating the project, by pasting them or dropping a .env file.")
                    .font(.callout).foregroundStyle(.tertiary)
            }

            VStack(spacing: 0) {
                ForEach(Array(scan.envFiles.enumerated()), id: \.element.id) { index, file in
                    if index > 0 { Divider().padding(.leading, 40) }
                    fileRow(file)
                }
                if let example = scan.exampleFile {
                    if !scan.envFiles.isEmpty { Divider().padding(.leading, 40) }
                    exampleRow(example, count: scan.expected.count)
                }
            }
            .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 14))

            if scan.envFiles.contains(where: { $0.ignoredByGit == false && include.contains($0.id) }) {
                Label("Some of these files aren't in .gitignore, so git could commit them. Slinky won't change your files; add them to .gitignore to keep them out of git.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !scan.expected.isEmpty {
                let missing = stillMissing(scan)
                Label(missing.isEmpty ? "Everything in \(scan.exampleFile ?? ".env.example") is covered."
                                      : "Still missing after import: " + missing.prefix(5).joined(separator: ", ") + (missing.count > 5 ? " and \(missing.count - 5) more" : ""),
                      systemImage: missing.isEmpty ? "checkmark.circle" : "circle.dashed")
                    .font(.caption)
                    .foregroundStyle(missing.isEmpty ? Color.green : Color.secondary)
            }
        }
    }

    private func fileRow(_ file: ProjectScan.EnvFile) -> some View {
        let on = include.contains(file.id)
        return HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { on }, set: { if $0 { include.insert(file.id) } else { include.remove(file.id) } }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(file.fileName).font(.system(size: 13, weight: .semibold, design: .monospaced))
                    if file.ignoredByGit == false { Chip(text: "Not in .gitignore", style: .warn) }
                }
                Text(file.lines.isEmpty ? "No variables" : "\(file.lines.count) \(file.lines.count == 1 ? "variable" : "variables") · " + file.names.prefix(3).joined(separator: ", ") + (file.lines.count > 3 ? "…" : ""))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Menu {
                ForEach(AppEnvironment.allCases) { e in
                    Button(e.title) { environments[file.id] = e }
                }
            } label: {
                ChipLabel(symbol: "circle.lefthalf.filled", text: environment(of: file).title, menu: true)
            }
            .menuStyle(.button)
            .buttonStyle(ChipButtonStyle(selected: on))
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(!on)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .opacity(on ? 1 : 0.55)
    }

    private func exampleRow(_ name: String, count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13, weight: .semibold, design: .monospaced))
                Text("\(count) names. Slinky uses these to show which variables are missing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Label("Encrypted on this Mac", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Cancel", action: close)
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.glass)
                .controlSize(.large)
            Button(action: create) {
                HStack(spacing: 8) {
                    Text(importCount == 0 ? "Create Project" : "Create and Import \(importCount) \(importCount == 1 ? "Variable" : "Variables")")
                    Text("↵").font(.callout.weight(.semibold)).opacity(0.6)
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(trimmedName.isEmpty)
        }
    }

    // MARK: Behavior

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private func environment(of file: ProjectScan.EnvFile) -> AppEnvironment {
        environments[file.id] ?? file.environment
    }

    private var chosenFiles: [ProjectScan.EnvFile] {
        scan?.envFiles.filter { include.contains($0.id) } ?? []
    }

    /// Distinct variable names across the chosen files.
    private var importCount: Int {
        Set(chosenFiles.flatMap(\.names)).count
    }

    private func stillMissing(_ scan: ProjectScan) -> [String] {
        let have = Set(chosenFiles.flatMap(\.names))
        return scan.expected.filter { !have.contains($0) }
    }

    private func use(_ folder: URL) {
        let result = ProjectScan.scan(folder)
        scan = result
        include = Set(result.envFiles.filter { !$0.lines.isEmpty }.map(\.id))
        environments = [:]
        if !nameTouched || trimmedName.isEmpty {
            name = result.suggestedName
            nameTouched = false
        }
    }

    private func unlink() {
        scan = nil
        include = []
        environments = [:]
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"
        panel.message = "Choose the project folder. Slinky reads its .env files and never changes them."
        if panel.runModal() == .OK, let url = panel.url { use(url) }
    }

    private func create() {
        guard !trimmedName.isEmpty else { return }
        model.createProject(name: trimmedName, folder: scan?.folder, expected: scan?.expected ?? [],
                            imports: chosenFiles.map { (lines: $0.lines, env: environment(of: $0)) })
        close()
    }
}
