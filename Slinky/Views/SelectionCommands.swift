import SlinkyCoreShared
import SwiftUI

/// What the screen in front can do with what's selected, for the Edit menu's shortcuts. Every copy goes through
/// the model's `copy`, so the clipboard rules (concealed, this Mac only, cleared after a while) always apply.
struct SelectionActions {
    var edit: (() -> Void)?
    /// `NAME=value`, for pasting into a .env file.
    var copyLine: (() -> Void)?
    /// `export NAME='value'`, for pasting into a terminal.
    var copyExport: (() -> Void)?
    /// The name alone, no value: for `process.env.NAME` in code.
    var copyName: (() -> Void)?
}

extension FocusedValues {
    @Entry var selectionActions: SelectionActions?
}

/// Edit › Copy as NAME=value (⇧⌘C), Copy as export Line, Copy Name (⌥⌘C) and Edit… (⌘E); View › the places (⌘1–⌘7).
struct SelectionCommands: Commands {
    let model: AppModel
    @FocusedValue(\.selectionActions) private var actions

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy as NAME=value") { actions?.copyLine?() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(actions?.copyLine == nil || model.panelOpen)
            Button("Copy as export Line") { actions?.copyExport?() }
                .disabled(actions?.copyExport == nil || model.panelOpen)
            Button("Copy Name") { actions?.copyName?() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(actions?.copyName == nil || model.panelOpen)
            Divider()
            Button("Edit…") { actions?.edit?() }
                .keyboardShortcut("e")
                .disabled(actions?.edit == nil || model.panelOpen)
        }
        CommandGroup(before: .sidebar) {
            place("All Items", .library(.all), "1")
            place("Keys & Tokens", .library(.keys), "2")
            place("Recovery Codes", .library(.codes), "3")
            place("Recovery Keys", .library(.recoveryKeys), "4")
            place("Health", .attention, "5")
            place("Recently Deleted", .trash, "6")
            place("Activity", .activity, "7")
            place("People", .people, "8")
            Divider()
        }
    }

    private func place(_ title: String, _ item: SidebarItem, _ key: KeyEquivalent) -> some View {
        Button(title) {
            model.searchText = ""
            model.selection = item
        }
        .keyboardShortcut(key)
        .disabled(!model.isUnlocked || model.panelOpen)
    }
}

extension SelectionActions {
    /// What a library item offers: keys get every copy format; recovery keys and code sets a name; all can be edited.
    @MainActor
    static func library(_ ref: LibraryRef?, model: AppModel) -> SelectionActions? {
        guard let ref else { return nil }
        var actions = SelectionActions(edit: { model.editing = ref.editTarget })
        switch ref {
        case let .key(id):
            guard let key = model.document.keys.first(where: { $0.id == id }) else { return actions }
            actions.copyLine = { model.copy("\(key.name)=\(key.value)", label: "\(key.name)=…", provider: key.provider) }
            actions.copyExport = { model.copy(Broker.shellExports([key.name: key.value]), label: "export \(key.name)", provider: key.provider) }
            actions.copyName = { model.copyName(key.name) }
        case let .kept(id):
            if let item = model.document.kept.first(where: { $0.id == id }) { actions.copyName = { model.copyName(item.label) } }
        case let .codes(id):
            if let set = model.document.codeSets.first(where: { $0.id == id }) { actions.copyName = { model.copyName(set.account) } }
        case let .file(id):
            if let file = model.document.secretFiles.first(where: { $0.id == id }) { actions.copyName = { model.copyName(file.name) } }
        }
        return actions
    }
}
