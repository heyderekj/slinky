import AppKit
import ServiceManagement

/// Settings. Plain values in UserDefaults: timings, toggles and a copy count. Never a secret, a name or a value.
@Observable
final class Preferences {
    static let shared = Preferences()

    static let autoLockChoices = [5, 10, 30, 60]
    static let clipboardChoices = [30, 60, 90, 120]

    private let defaults = UserDefaults.standard

    /// Lock after this many minutes without using the Mac.
    var autoLockMinutes: Int { didSet { defaults.set(autoLockMinutes, forKey: "autoLockMinutes") } }
    var lockOnScreenLock: Bool { didSet { defaults.set(lockOnScreenLock, forKey: "lockOnScreenLock") } }
    var lockOnSleep: Bool { didSet { defaults.set(lockOnSleep, forKey: "lockOnSleep") } }
    /// The clipboard clears this many seconds after Slinky copies something (if nothing else was copied since).
    var clipboardSeconds: Int { didSet { defaults.set(clipboardSeconds, forKey: "clipboardSeconds") } }
    var playSounds: Bool { didSet { defaults.set(playSounds, forKey: "playSounds") } }
    var showInMenuBar: Bool { didSet { defaults.set(showInMenuBar, forKey: "showInMenuBar") } }
    /// Ask GitHub once a day whether there's a newer Slinky. The only network request Slinky makes.
    var checkForUpdates: Bool { didSet { defaults.set(checkForUpdates, forKey: "checkForUpdates") } }
    /// How many times Slinky has copied something for you. A count only, for the About pane.
    var copyCount: Int { didSet { defaults.set(copyCount, forKey: "copyCount") } }
    /// Mirrors macOS's Login Items. Read fresh from the system when Settings opens.
    private(set) var openAtLogin = false

    private init() {
        defaults.register(defaults: [
            "autoLockMinutes": 10, "lockOnScreenLock": true, "lockOnSleep": true,
            "clipboardSeconds": 60, "playSounds": true, "showInMenuBar": true, "checkForUpdates": true, "copyCount": 0,
        ])
        autoLockMinutes = defaults.integer(forKey: "autoLockMinutes")
        lockOnScreenLock = defaults.bool(forKey: "lockOnScreenLock")
        lockOnSleep = defaults.bool(forKey: "lockOnSleep")
        clipboardSeconds = defaults.integer(forKey: "clipboardSeconds")
        playSounds = defaults.bool(forKey: "playSounds")
        showInMenuBar = defaults.bool(forKey: "showInMenuBar")
        checkForUpdates = defaults.bool(forKey: "checkForUpdates")
        copyCount = defaults.integer(forKey: "copyCount")
        refreshLoginItem()
    }

    func refreshLoginItem() {
        openAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Returns a plain message if macOS said no (for example, it needs approval in System Settings).
    func setOpenAtLogin(_ on: Bool) -> String? {
        defer { refreshLoginItem() }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            if SMAppService.mainApp.status == .requiresApproval {
                return "macOS needs your OK. Turn Slinky on in System Settings › General › Login Items."
            }
            return "macOS didn't allow that change. Try again from System Settings › General › Login Items."
        }
    }
}

/// System sounds only (no audio files), and only when "Play sounds" is on. Like Dinky: a bigger moment, a bigger sound.
enum Sounds {
    enum Moment {
        case saved, imported, locked

        var name: String {
            switch self {
            case .saved: "Pop"
            case .imported: "Glass"
            case .locked: "Tink"
            }
        }
    }

    @MainActor
    static func play(_ moment: Moment) {
        guard Preferences.shared.playSounds else { return }
        NSSound(named: NSSound.Name(moment.name))?.play()
    }
}

