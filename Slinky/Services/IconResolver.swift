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
/// the bundled service logo, the website's own icon (only if one was loaded), then initials. Everything here
/// is offline except WebsiteIcons, which runs only when the person turns it on or asks for one item.
@MainActor @Observable
final class IconResolver {
    static let shared = IconResolver()

    enum Resolved: Equatable {
        case app(NSImage)
        case logo(Service)
        case website(NSImage)
        case monogram(String)
    }

    @ObservationIgnored private var appIcons: [String: NSImage] = [:]
    @ObservationIgnored private var missingApps: Set<String> = []
    @ObservationIgnored private var matches: [IconSubject: Service?] = [:]
    /// Apple Intelligence's guesses, for names the catalog didn't recognize. Memory only.
    private var guesses: [String: String] = [:]
    @ObservationIgnored private var asked: Set<String> = []
    /// Website icons from the vault, by domain. Only while unlocked.
    private var siteImages: [String: NSImage] = [:]
    @ObservationIgnored private var fetched: Set<String> = []
    /// Saves a fetched website icon into the vault (set by AppModel).
    @ObservationIgnored var saveSiteIcon: ((String, Data) -> Void)?

    /// Forgets everything it worked out. Called on lock, with the vault's site icons gone too.
    func reset() {
        matches = [:]
        guesses = [:]
        asked = []
        siteImages = [:]
        fetched = []
    }

    /// Keeps the decoded website icons in step with the vault.
    func load(siteIcons: [String: Data]?) {
        let icons = siteIcons ?? [:]
        guard Set(icons.keys) != Set(siteImages.keys) else { return }
        siteImages = icons.compactMapValues { NSImage(data: $0) }
    }

    func resolve(_ subject: IconSubject) -> Resolved {
        let initials = subject.provider ?? subject.from ?? subject.name
        switch subject.choice {
        case let .app(bundleID)?:
            if let image = appIcon(bundleID) { return .app(image) }
        case let .service(id)?:
            if let s = ServiceCatalog.service(id: id) { return resolved(s, initials: initials) }
        case .monogram?:
            return .monogram(initials)
        case let .website(domain)?:
            if let image = siteImages[domain] { return .website(image) }
        case .automatic?, nil:
            break
        }
        let service = service(for: subject)
        if let service, let r = appOrLogo(service) { return r }
        if let host = websiteHost(subject), let image = siteImages[host] { return .website(image) }
        return .monogram(service?.name ?? initials)
    }

    /// The website an item's icon could come from: its link, else the service's own site.
    func websiteHost(_ subject: IconSubject) -> String? {
        if case let .website(domain)? = subject.choice { return domain }
        return Links.host(of: subject.link) ?? service(for: subject)?.domains.first
    }

    func hasSiteIcon(_ domain: String) -> Bool { siteImages[domain] != nil }

    /// With "Load icons from websites" on: an item that would otherwise show initials gets its site's icon.
    func fetchIfAllowed(_ subject: IconSubject) {
        guard Preferences.shared.loadWebsiteIcons, subject.choice != .monogram,
              case .monogram = resolve(subject), let host = websiteHost(subject),
              siteImages[host] == nil, fetched.insert(host).inserted else { return }
        Task { _ = await loadSiteIcon(host) }
    }

    /// Fetches one site's icon now and keeps it in the vault. False if the site had none Slinky could use.
    func loadSiteIcon(_ domain: String) async -> Bool {
        fetched.insert(domain)
        guard let png = try? await WebsiteIcons.fetch(domain: domain), let image = NSImage(data: png) else { return false }
        siteImages[domain] = image
        saveSiteIcon?(domain, png)
        return true
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
        appOrLogo(s) ?? .monogram(s.name)
    }

    private func appOrLogo(_ s: Service) -> Resolved? {
        for id in s.bundleIDs { if let image = appIcon(id) { return .app(image) } }
        return s.hasLogo ? .logo(s) : nil
    }

    /// Looks up the Mac apps of every service Slinky knows, once, off the main thread, so icons are ready before
    /// the first unlock and loading them never stalls the unlock animation. Uses only the built-in catalog.
    func warmUp() {
        let ids = ServiceCatalog.all.flatMap(\.bundleIDs)
        Task.detached(priority: .utility) {
            var found: [String: NSImage] = [:]
            var missing: Set<String> = []
            for id in ids {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                    let image = NSWorkspace.shared.icon(forFile: url.path)
                    image.size = NSSize(width: 64, height: 64)
                    found[id] = image
                } else {
                    missing.insert(id)
                }
            }
            await MainActor.run { [found, missing] in
                IconResolver.shared.appIcons.merge(found) { current, _ in current }
                IconResolver.shared.missingApps.formUnion(missing)
            }
        }
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
