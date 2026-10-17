import AppIntents
import LocalAuthentication
import SlinkyCoreShared

// Shortcuts support. The rule: values never leave Slinky through Shortcuts.
// No action returns a value. "Copy" puts it on the clipboard the usual way (concealed, clears in 60 seconds)
// and asks for Touch ID every time, because any app can run a shortcut.

/// An item as Shortcuts sees it: its name and where it lives. Never its value.
struct SlinkyItemEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Slinky Item"
    static let defaultQuery = SlinkyItemQuery()

    let id: String
    let title: String
    let subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
    }
}

struct SlinkyItemQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [SlinkyItemEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [SlinkyItemEntity] {
        let q = string.lowercased()
        return all().filter { $0.title.lowercased().contains(q) || $0.subtitle.lowercased().contains(q) }
    }

    @MainActor
    func suggestedEntities() async throws -> [SlinkyItemEntity] { all() }

    /// Names are only listed while Slinky is unlocked.
    @MainActor
    private func all() -> [SlinkyItemEntity] {
        guard AppModel.shared.isUnlocked else { return [] }
        return AppModel.shared.quickItems.map { SlinkyItemEntity(id: $0.id, title: $0.title, subtitle: $0.subtitle) }
    }
}

enum SlinkyIntentError: Error, CustomLocalizedStringResourceConvertible {
    case locked, notFound, notConfirmed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .locked: "Slinky is locked. Unlock Slinky, then run this again."
        case .notFound: "That item isn't in Slinky anymore."
        case .notConfirmed: "Copy was cancelled."
        }
    }
}

struct CopyFromSlinkyIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy from Slinky"
    static let description = IntentDescription("Copies an item to the clipboard after you confirm with Touch ID. The clipboard clears in 60 seconds.")

    @Parameter(title: "Item") var item: SlinkyItemEntity

    static var parameterSummary: some ParameterSummary { Summary("Copy \(\.$item) from Slinky") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        guard model.isUnlocked else { throw SlinkyIntentError.locked }
        guard let found = model.quickItems.first(where: { $0.id == item.id }) else { throw SlinkyIntentError.notFound }
        let context = LAContext()
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "copy \(found.title)")
        } catch {
            throw SlinkyIntentError.notConfirmed
        }
        if case let .codes(setID) = found.kind, let index = model.document.codeSets.first(where: { $0.id == setID })?.nextUnused {
            model.useCode(index, in: setID)
        } else {
            model.copy(found.value, label: found.title, provider: found.provider)
        }
        return .result(dialog: "Copied \(found.title). \(AppModel.clipboardNote)")
    }
}

struct AddToSlinkyIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Slinky"
    static let description = IntentDescription("Opens Add Item with the text filled in, so you can check where it goes and save it. Try it with Get Clipboard.")
    static let openAppWhenRun = true

    @Parameter(title: "Text") var text: String

    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$text) to Slinky") }

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = AppModel.shared
        model.openMainWindow?()
        guard model.isUnlocked else { throw SlinkyIntentError.locked }
        model.tuckPrefill = text
        model.tuckProject = nil
        model.showTuck = true
        return .result()
    }
}

struct LockSlinkyIntent: AppIntent {
    static let title: LocalizedStringResource = "Lock Slinky"
    static let description = IntentDescription("Locks Slinky right away.")

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.lock(reason: .manual)
        return .result()
    }
}

struct OpenQuickAccessIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Quick Access"
    static let description = IntentDescription("Opens Slinky's Quick Access, the same as ⌥⌘K.")

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickAccess.shared.show()
        return .result()
    }
}

struct SlinkyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddToSlinkyIntent(), phrases: ["Add to \(.applicationName)"],
                    shortTitle: "Add to Slinky", systemImageName: "plus")
        AppShortcut(intent: CopyFromSlinkyIntent(), phrases: ["Copy from \(.applicationName)"],
                    shortTitle: "Copy from Slinky", systemImageName: "doc.on.doc")
        AppShortcut(intent: OpenQuickAccessIntent(), phrases: ["Open \(.applicationName) Quick Access"],
                    shortTitle: "Quick Access", systemImageName: "magnifyingglass")
        AppShortcut(intent: LockSlinkyIntent(), phrases: ["Lock \(.applicationName)"],
                    shortTitle: "Lock Slinky", systemImageName: "lock")
    }
}
