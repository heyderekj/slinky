import AppKit
import Observation
import SlinkyCoreShared

/// What an item's icon is worked out from. Names, links and notes only: never a value.
struct IconSubject: Hashable {
    var name: String
    var from: String? = nil
    var provider: String? = nil
    var link: String? = nil
    var note: String? = nil
    var choice: IconChoice? = nil
}

extension Key { var iconSubject: IconSubject { IconSubject(name: name, provider: provider, link: link, note: note, choice: icon) } }
extension CodeSet { var iconSubject: IconSubject { IconSubject(name: account, from: username, link: link, note: note, choice: icon) } }
extension KeptItem { var iconSubject: IconSubject { IconSubject(name: label, from: from, link: link, note: note, choice: icon) } }
extension Variable { var iconSubject: IconSubject { IconSubject(name: name, provider: provider, link: link, note: note, choice: icon) } }

/// Picks each item's icon, in this order: the person's own choice, the service's Mac app if it's installed,
/// the bundled service logo, then initials. Everything here is offline. Website icons come in only when
/// the person turns them on (WebsiteIcons).
@MainActor @Observable
final class IconResolver {
    static let shared = IconResolver()

    enum Resolved: Equatable {
        case app(NSImage)
        case logo(Service)
        case monogram(String)
    }

    @ObservationIgnored private var appIcons: [String: NSImage] = [:]
    @ObservationIgnored private var missingApps: Set<String> = []
    @ObservationIgnored private var matches: [IconSubject: Service?] = [:]
    /// Apple Intelligence's guesses, for names the catalog didn't recognize. Memory only.
    private var guesses: [String: String] = [:]
    @ObservationIgnored private var asked: Set<String> = []

    func resolve(_ subject: IconSubject) -> Resolved {
        let initials = subject.provider ?? subject.from ?? subject.name
        switch subject.choice {
        case let .app(bundleID)?:
            if let image = appIcon(bundleID) { return .app(image) }
        case let .service(id)?:
            if let s = ServiceCatalog.service(id: id) { return resolved(s, initials: initials) }
        case .monogram?:
            return .monogram(initials)
        case .website?, .automatic?, nil:
            break
        }
        if let s = service(for: subject) { return resolved(s, initials: initials) }
        return .monogram(initials)
    }

    /// The service this item is for, if Slinky can tell.
    func service(for subject: IconSubject) -> Service? {
        if case let .service(id)? = subject.choice { return ServiceCatalog.service(id: id) }
        let key = IconSubject(name: subject.name, from: subject.from, provider: subject.provider, link: subject.link, note: subject.note)
        if let cached = matches[key] { return cached ?? guessed(subject) }
        let found = ServiceCatalog.match(name: subject.name, from: subject.from, provider: subject.provider,
                                         link: subject.link, note: subject.note)
        matches[key] = found
        return found ?? guessed(subject)
    }

    private func resolved(_ s: Service, initials: String) -> Resolved {
        for id in s.bundleIDs { if let image = appIcon(id) { return .app(image) } }
        return s.hasLogo ? .logo(s) : .monogram(s.name)
    }

    func appIcon(_ bundleID: String) -> NSImage? {
        if let image = appIcons[bundleID] { return image }
        guard !missingApps.contains(bundleID) else { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            missingApps.insert(bundleID)
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        appIcons[bundleID] = image
        return image
    }

    // MARK: Apple Intelligence

    private static func guessKey(_ s: IconSubject) -> String {
        [s.name, s.from ?? "", Links.host(of: s.link) ?? ""].joined(separator: "\u{1F}").lowercased()
    }

    private func guessed(_ subject: IconSubject) -> Service? {
        guesses[Self.guessKey(subject)].flatMap(ServiceCatalog.service(id:))
    }

    /// For a name the catalog doesn't know, ask the on-device model once per launch. Only the name, where it's
    /// from and the link's website go in, never a value or a note, and nothing leaves the Mac.
    func guessIfNeeded(_ subject: IconSubject) {
        guard subject.choice == nil || subject.choice == .automatic,
              !subject.name.trimmingCharacters(in: .whitespaces).isEmpty,
              service(for: subject) == nil else { return }
        let key = Self.guessKey(subject)
        guard asked.insert(key).inserted else { return }
        guard #available(macOS 26, *) else { return }
        Task {
            if let id = await ServiceGuesser.guess(name: subject.name, from: subject.from, host: Links.host(of: subject.link)) {
                guesses[key] = id
            }
        }
    }
}
