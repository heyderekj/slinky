import SlinkyCoreShared
import SwiftUI
import UniformTypeIdentifiers

extension AppModel {
    /// File › Import… Picks the file, then reads it like a dropped one: an export opens the import panel, a .env
    /// file or a folder opens the folder review.
    func beginImport() {
        let panel = NSOpenPanel()
        panel.message = "Choose an export from another app (.1pux, .csv or .txt), or a .env file. Slinky picks out keys, tokens and recovery codes, and skips passwords."
        panel.prompt = "Read File"
        panel.showsHiddenFiles = true   // .env files start with a dot
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open([url], on: .window)
    }

    /// Reads an export in memory and opens the import panel.
    func openImport(_ url: URL) {
        do {
            let result = try Importer.read(url)
            showTuck = false
            review = nil
            editing = nil
            importSource = url
            importing = result
        } catch let error as Importer.ImportError {
            show(error.description, style: .info)
        } catch {
            show("Slinky couldn't read that file.", style: .info)
        }
    }
}

struct ImportOverlay: View {
    @Environment(AppModel.self) private var model
    let result: Importer.Result

    var body: some View {
        ZStack {
            PanelBackdrop(close: close)
            ImportPanel(result: result, close: close)
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            model.importing = nil
            model.importSource = nil
        }
    }
}

/// Shows what Slinky found in the export: names and peeks only, never values. Items already in Slinky
/// start unchecked. Passwords were left out on purpose, and the screen says so.
private struct ImportPanel: View {
    @Environment(AppModel.self) private var model
    let result: Importer.Result
    let close: () -> Void

    @State private var chosen: Set<UUID> = []
    /// Names as edited in the list; an empty one falls back to the name Slinky found.
    @State private var names: [UUID: String] = [:]
    @State private var trashExport = true
    @State private var appeared = false

    private var fileName: String { model.importSource?.lastPathComponent ?? "the file" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.14), in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Import").font(.headline)
                    Text(fileName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                PanelCloseButton(action: close)
            }
            .padding(.bottom, 12)

            if result.candidates.isEmpty {
                Text("Slinky didn't find any API keys, tokens, recovery codes or recovery keys in \(fileName).")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.paper, in: .rect(cornerRadius: 18))
            } else {
                HStack {
                    Text("Found \(result.candidates.count) \(result.candidates.count == 1 ? "item" : "items")").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button(chosen.count == result.candidates.count ? "Select None" : "Select All") {
                        chosen = chosen.count == result.candidates.count ? [] : Set(result.candidates.map(\.id))
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.bottom, 8)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(result.candidates.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Divider().padding(.leading, 76) }
                            row(item)
                        }
                    }
                }
                .frame(maxHeight: 300)
                .background(Color.paper, in: .rect(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 6) {
                if result.skippedPasswords > 0 {
                    Label("Skipped \(result.skippedPasswords) \(result.skippedPasswords == 1 ? "password or login" : "passwords and logins"). Those belong in Apple Passwords.",
                          systemImage: "key.horizontal")
                }
                if result.skippedOther > 0 {
                    Label("Skipped \(result.skippedOther) other \(result.skippedOther == 1 ? "item" : "items") that aren't keys or recovery codes.",
                          systemImage: "minus.circle")
                }
                Toggle("Move \(fileName) to the Trash after importing. Export files aren't encrypted.", isOn: $trashExport)
                    .toggleStyle(.checkbox)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 14)

            HStack(spacing: 10) {
                EncryptedNote()
                Spacer()
                Button("Cancel", action: close)
                    .keyboardShortcut(.cancelAction)
                    .glassButton()
                Button(action: importChosen) {
                    HStack(spacing: 8) {
                        Text(chosen.isEmpty ? "Import" : "Import \(chosen.count) \(chosen.count == 1 ? "Item" : "Items")")
                        Text("↵").font(.callout.weight(.semibold)).opacity(0.6)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .glassProminentButton()
                .disabled(chosen.isEmpty)
            }
            .dialogButtons()
            .padding(.top, 14)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 680)
        .glass(in: .rect(cornerRadius: 28))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 14)
        .panelEntrance(appeared)
        .onAppear {
            // Everything starts checked except what's already in Slinky.
            chosen = Set(result.candidates.filter { !isDuplicate($0) }.map(\.id))
            withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) { appeared = true }
        }
    }

    private func row(_ item: Importer.Candidate) -> some View {
        let on = chosen.contains(item.id)
        let duplicate = isDuplicate(item)
        return HStack(spacing: 12) {
            Toggle(item.name, isOn: Binding(get: { on }, set: { if $0 { chosen.insert(item.id) } else { chosen.remove(item.id) } }))
                .toggleStyle(.checkbox)
                .labelsHidden()
            ServiceIcon(subject: IconSubject(name: item.name, provider: provider(item)), size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    // The name can be changed here, before anything is saved.
                    TextField("Name", text: Binding(get: { names[item.id] ?? item.name }, set: { names[item.id] = $0 }))
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .font(isKey(item) ? .body.monospaced().weight(.semibold) : .body.weight(.semibold))
                        .limit(Binding(get: { names[item.id] ?? item.name }, set: { names[item.id] = $0 }), to: FieldLimit.name)
                        .help("Click to rename before importing")
                    if duplicate { Chip(text: "Already in Slinky", style: .warn) }
                }
                Text(subtitle(item)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(peek(item))
                .font(.callout.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .opacity(on ? 1 : 0.55)
    }

    private func isKey(_ item: Importer.Candidate) -> Bool {
        if case .key = item.kind { return true }
        return false
    }

    private func provider(_ item: Importer.Candidate) -> String? {
        if case let .key(provider, _, _) = item.kind { return provider }
        return nil
    }

    private func subtitle(_ item: Importer.Candidate) -> String {
        let place: String
        switch item.kind {
        case let .key(provider, isLive, _): place = "Keys & Tokens" + (provider.map { " · \($0)" } ?? "") + (isLive ? " · live" : "")
        case let .codes(codes): place = "Recovery Codes · \(codes.count) codes"
        case .recoveryKey: place = "Recovery Keys"
        }
        return place + " · from " + item.source
    }

    private func peek(_ item: Importer.Candidate) -> String {
        if case let .codes(codes) = item.kind { return "\(codes.count) codes" }
        return Peek.of(item.value)
    }

    private func isDuplicate(_ item: Importer.Candidate) -> Bool {
        if case let .codes(codes) = item.kind { return !model.places(ofCodes: codes).isEmpty }
        return !model.places(of: item.value).isEmpty
    }

    private func importChosen() {
        let items = result.candidates.filter { chosen.contains($0.id) }.map { item -> Importer.Candidate in
            var item = item
            let name = (names[item.id] ?? "").trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { item.name = name }
            return item
        }
        guard !items.isEmpty else { return }
        let source = model.importSource
        let left = result.candidates.filter { !chosen.contains($0.id) }
        let unchanged = left.filter(isDuplicate).count
        let skipped = left.count - unchanged + result.skippedPasswords + result.skippedOther
        let saved = model.importItems(items, unchanged: unchanged, skipped: skipped, from: source?.lastPathComponent)
        // Only once the items are safely in the vault does the export go.
        if saved, trashExport, let source, !model.isDemoMode {
            // The Trash, not a permanent delete: it can be put back.
            NSWorkspace.shared.recycle([source]) { _, error in
                if error != nil {
                    Task { @MainActor in AppModel.shared.show("Couldn't move \(source.lastPathComponent) to the Trash. Delete it yourself when you're done.", style: .info) }
                }
            }
        }
        close()
    }
}
