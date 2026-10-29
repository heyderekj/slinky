#if DEBUG
import AppKit
import SlinkyCoreShared
import SwiftUI

/// Debug builds: `Slinky --render-snapshots <folder>` draws the main screens with the demo vaults at a few window
/// sizes and saves PNGs, then quits. It never opens the real vault. Glass and materials come out flat (they're drawn
/// by the window server), so these are for layout: overflow, truncation, wrapping, counts.
@MainActor
enum SnapshotRunner {
    struct Shot {
        let name: String
        let fixture: DemoFixture
        let setup: @MainActor (AppModel) -> Void
    }

    static let sizes: [CGSize] = [CGSize(width: 880, height: 560), CGSize(width: 1100, height: 680), CGSize(width: 1440, height: 900)]

    static var shots: [Shot] {
        [
            Shot(name: "library", fixture: .worst) { m in m.librarySelection = m.document.keys.first.map { .key($0.id) } },
            Shot(name: "plain-library", fixture: .worst) { _ in },
            Shot(name: "library-codes", fixture: .worst) { m in m.librarySelection = m.document.codeSets.first.map { .codes($0.id) } },
            Shot(name: "library-file", fixture: .worst) { m in m.librarySelection = m.document.secretFiles.first.map { .file($0.id) } },
            Shot(name: "library-short-key", fixture: .worst) { m in m.librarySelection = m.document.keys.first { $0.name == "SHORT_TOKEN" }.map { .key($0.id) } },
            Shot(name: "add-verum", fixture: .worst) { m in m.openAddItem(prefill: "VERUM_SETUP_TEST=placeholder") },
            Shot(name: "add-verum-hidden-chars", fixture: .empty) { m in m.openAddItem(prefill: "\u{200B}`VERUM_SETUP_TEST=placeholder`") },
            Shot(name: "add-key", fixture: .worst) { m in m.openAddItem(prefill: "sk_live_EXAMPLE4f2aXX") },
            Shot(name: "add-codes", fixture: .worst) { m in m.openAddItem(prefill: (0..<10).map { "ex\($0)00-mpl\($0)0" }.joined(separator: "\n")) },
            Shot(name: "add-env", fixture: .worst) { m in m.openAddItem(prefill: (0..<8).map { "SERVICE_\($0)_API_KEY=EXAMPLE\($0)" }.joined(separator: "\n")) },
            Shot(name: "edit-key", fixture: .worst) { m in m.editing = m.document.keys.first.map { .key($0.id) } },
            Shot(name: "edit-codes", fixture: .worst) { m in m.editing = m.document.codeSets.first.map { .codes($0.id) } },
            Shot(name: "review-update", fixture: .worst) { m in
                guard let p = m.document.projects.first else { return }
                m.selection = .project(p.id)
                m.review = FolderReview(target: .project(p.id), scans: DemoFixture.reviewScans(for: p))
            },
            Shot(name: "review-new", fixture: .worst) { m in m.review = FolderReview(target: .newProject, scans: DemoFixture.reviewScans(for: nil)) },
            Shot(name: "project", fixture: .worst) { m in m.selection = m.document.projects.first.map { .project($0.id) } },
            Shot(name: "health", fixture: .worst) { m in m.selection = .attention },
            Shot(name: "activity", fixture: .worst) { m in m.selection = .activity },
            Shot(name: "trash", fixture: .worst) { m in m.selection = .trash },
            Shot(name: "empty", fixture: .empty) { _ in },
            Shot(name: "one-library", fixture: .one) { m in m.librarySelection = m.document.codeSets.first.map { .codes($0.id) } },
            Shot(name: "one-health", fixture: .one) { m in m.selection = .attention },
            Shot(name: "one-project", fixture: .one) { m in m.selection = m.document.projects.first.map { .project($0.id) } },
            Shot(name: "thousand", fixture: .thousand) { _ in },
            Shot(name: "share", fixture: .worst) { m in
                m.document.people = demoPeople
                m.sharing = ShareDraft(items: m.sharedItems(m.document.keys.prefix(3).map { .key($0.id) }))
            },
            Shot(name: "share-nobody", fixture: .worst) { m in
                m.sharing = ShareDraft(items: m.sharedItems(m.document.keys.prefix(1).map { .key($0.id) }))
            },
            Shot(name: "receive-stranger", fixture: .worst) { m in
                m.receiving = ReceivedShare(from: demoCard("Ana"), made: .now,
                                            items: SharedItems(keys: Array(m.document.keys.prefix(2)),
                                                               variables: m.document.projects.first?.variables.prefix(3).map { $0 } ?? [],
                                                               projectName: m.document.projects.first?.name),
                                            known: nil)
            },
            Shot(name: "receive-known", fixture: .worst) { m in
                m.document.people = demoPeople
                m.receiving = ReceivedShare(from: demoPeople[0].cards[0], made: .now,
                                            items: SharedItems(keys: Array(m.document.keys.prefix(4))), known: demoPeople[0])
            },
        ]
    }

    /// Made-up public keys, so the codes look real and mean nothing.
    static func demoCard(_ name: String) -> PersonCard {
        var bytes = Data([0x04]) + Data(name.utf8)
        bytes += Data(repeating: 0x5A, count: 65 - bytes.count)
        return PersonCard(id: UUID(), name: name, agreement: bytes, signing: Data(bytes.reversed()))
    }

    static var demoPeople: [Person] {
        [Person(name: "Ana", cards: [demoCard("Ana")], checked: true),
         Person(name: "Ben Okafor-Lindqvist", cards: [demoCard("Ben"), demoCard("Ben2")], checked: false)]
    }

    static func run(folder: String, only: String?) {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
        let out = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let model = AppModel.shared
        for shot in shots where only == nil || shot.name.contains(only!) {
            for size in sizes {
                model.startDemo(shot.fixture)
                shot.setup(model)
                let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
                                      styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
                window.titlebarAppearsTransparent = true
                let host = NSHostingView(rootView: RootView().symbolVariant(.fill).environment(model))
                host.frame = NSRect(origin: .zero, size: size)
                window.contentView = host
                window.orderFrontRegardless()
                RunLoop.main.run(until: Date().addingTimeInterval(1.2))
                host.layoutSubtreeIfNeeded()
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    let file = out.appendingPathComponent("\(shot.name)-\(Int(size.width)).png")
                    try? rep.representation(using: .png, properties: [:])?.write(to: file)
                }
                window.orderOut(nil)
            }
        }
    }
}
#endif
