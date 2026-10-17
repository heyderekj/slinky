import Foundation
import FoundationModels
import SlinkyCoreShared

/// Apple Intelligence's on-device model, asked which known service an item is for when the catalog's own
/// matching found nothing. Gets the item's name, where it's from and its link's website. Never a value.
@available(macOS 26, *)
@MainActor
enum ServiceGuesser {
    private static var queue: Task<Void, Never>?

    static func guess(name: String, from: String?, host: String?) async -> String? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        // One question at a time: the model runs on this Mac and shouldn't be flooded on a big library.
        let previous = queue
        let task = Task<String?, Never> {
            await previous?.value
            return await ask(name: name, from: from, host: host)
        }
        queue = Task { _ = await task.value }
        return await task.value
    }

    private static let none = "None of these"

    private static func ask(name: String, from: String?, host: String?) async -> String? {
        let names = ServiceCatalog.all.map(\.name) + [none]
        do {
            let pick = DynamicGenerationSchema(name: "ServiceName", anyOf: names)
            let root = DynamicGenerationSchema(name: "Answer", properties: [
                .init(name: "service", description: "The service this item belongs to", schema: pick),
            ])
            let schema = try GenerationSchema(root: root, dependencies: [])
            let session = LanguageModelSession(instructions: """
                You match a saved item (an API key, recovery codes or a recovery key) to the company or service it \
                belongs to, using only its name and website. Answer "\(none)" unless you are sure.
                """)
            var prompt = "Item name: \(name)"
            if let from, !from.isEmpty { prompt += "\nWebsite or app: \(from)" }
            if let host { prompt += "\nLink: \(host)" }
            let response = try await session.respond(to: prompt, schema: schema, options: GenerationOptions(temperature: 0))
            let answer = try response.content.value(String.self, forProperty: "service")
            guard answer != none else { return nil }
            return ServiceCatalog.all.first { $0.name == answer }?.id
        } catch {
            return nil
        }
    }
}
