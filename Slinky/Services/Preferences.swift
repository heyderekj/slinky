import AppKit
import ServiceManagement

/// Settings. Plain values in UserDefaults: timings, toggles and a copy count. Never a secret, a name or a value.
@Observable
final class Preferences {
    static let shared = Preferences()

    static let autoLockChoices = [5, 10, 30, 60]
    static let clipboardChoices = [30, 60, 90, 120]

    /// "30 seconds", "2 minutes": the same words in Settings and wherever Slinky says when the clipboard clears.
    static func clipboardDuration(_ seconds: Int) -> String {
        seconds >= 120 && seconds % 60 == 0 ? "\(seconds / 60) minutes" : "\(seconds) seconds"
    }

    private let defaults = UserDefaults.standard

    /// Lock after this many minutes without using the Mac.
    var autoLockMinutes: Int { didSet { defaults.set(autoLockMinutes, forKey: "autoLockMinutes") } }
    var lockOnScreenLock: Bool { didSet { defaults.set(lockOnScreenLock, forKey: "lockOnScreenLock") } }
    var lockOnSleep: Bool { didSet { defaults.set(lockOnSleep, forKey: "lockOnSleep") } }
    /// The clipboard clears this many seconds after Slinky copies something (if nothing else was copied since).
    var clipboardSeconds: Int { didSet { defaults.set(clipboardSeconds, forKey: "clipboardSeconds") } }
    var playSounds: Bool { didSet { defaults.set(playSounds, forKey: "playSounds") } }
    var showInMenuBar: Bool { didSet { defaults.set(showInMenuBar, forKey: "showInMenuBar") } }
    /// Ask GitHub once a day whether there's a newer Slinky.
    var checkForUpdates: Bool { didSet { defaults.set(checkForUpdates, forKey: "checkForUpdates") } }
    /// Fetch each saved website's own icon (off unless the person turns it on). See WebsiteIcons.
    var loadWebsiteIcons: Bool { didSet { defaults.set(loadWebsiteIcons, forKey: "loadWebsiteIcons") } }
    /// When Health last looked for saved values outside Slinky. A date only.
    var lastLeakCheck: Date { didSet { defaults.set(lastLeakCheck, forKey: "lastLeakCheck") } }
    /// The day of the last backup export (a date only, nothing about the vault), and whether the Recovery Key has
    /// changed since. Health asks for a backup when there's none in 30 days or the key changed.
    var lastBackup: Date? { didSet { defaults.set(lastBackup, forKey: "lastBackup") } }
    var newKeySinceBackup: Bool { didSet { defaults.set(newKeySinceBackup, forKey: "newKeySinceBackup") } }
    /// When Slinky started counting the 30 days for someone who's never exported a backup.
    var backupClockStart: Date { didSet { defaults.set(backupClockStart, forKey: "backupClockStart") } }
    /// Offer to save a key you copy in another app (it checks the shape only). Off unless turned on.
    var offerToSaveCopies: Bool { didSet { defaults.set(offerToSaveCopies, forKey: "offerToSaveCopies") } }
    /// Mac notifications for expiring keys, codes running low and leaks (names only). Off unless turned on.
    var reminders: Bool { didSet { defaults.set(reminders, forKey: "reminders") } }
    /// How many times Slinky has copied something for you. A count only, for the About pane.
    var copyCount: Int { didSet { defaults.set(copyCount, forKey: "copyCount") } }
    /// Mirrors macOS's Login Items. Read fresh from the system when Settings opens.
    private(set) var openAtLogin = false

    private init() {
        defaults.register(defaults: [
            "autoLockMinutes": 10, "lockOnScreenLock": true, "lockOnSleep": true,
            "clipboardSeconds": 60, "playSounds": true, "showInMenuBar": true, "checkForUpdates": true, "loadWebsiteIcons": false, "offerToSaveCopies": false, "reminders": false, "copyCount": 0,
        ])
        autoLockMinutes = defaults.integer(forKey: "autoLockMinutes")
        lockOnScreenLock = defaults.bool(forKey: "lockOnScreenLock")
        lockOnSleep = defaults.bool(forKey: "lockOnSleep")
        clipboardSeconds = defaults.integer(forKey: "clipboardSeconds")
        playSounds = defaults.bool(forKey: "playSounds")
        showInMenuBar = defaults.bool(forKey: "showInMenuBar")
        checkForUpdates = defaults.bool(forKey: "checkForUpdates")
        loadWebsiteIcons = defaults.bool(forKey: "loadWebsiteIcons")
        lastLeakCheck = defaults.object(forKey: "lastLeakCheck") as? Date ?? .distantPast
        lastBackup = defaults.object(forKey: "lastBackup") as? Date
        newKeySinceBackup = defaults.bool(forKey: "newKeySinceBackup")
        let clock = defaults.object(forKey: "backupClockStart") as? Date ?? .now
        if defaults.object(forKey: "backupClockStart") == nil { defaults.set(clock, forKey: "backupClockStart") }
        backupClockStart = clock
        offerToSaveCopies = defaults.bool(forKey: "offerToSaveCopies")
        reminders = defaults.bool(forKey: "reminders")
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

/// Only when "Play sounds" is on. Like Dinky: a bigger moment, a bigger sound.
/// Slinky's own sounds (Slinky/Sounds, made by design/sounds/make_sounds.py): the real sound of a Slinky's
/// coils settling, and a damped latch that feels solid. Quiet and mechanical, never cartoon.
enum Sounds {
    enum Moment: String {
        /// A short coil settle, then the latch closes.
        case saved
        /// A longer coil ripple, then the latch.
        case imported
        /// The coil closes up, then the bolt's two firm clicks. Timed to the keyhole closing.
        case locked
        /// The latch lets go, then the coil opens out. Timed to the keyhole opening.
        case unlocked
        /// Only the coil, short and soft: Health found nothing after Check Now.
        case clear
    }

    @MainActor private static var loaded: [Moment: NSSound] = [:]

    @MainActor
    static func play(_ moment: Moment) {
        guard Preferences.shared.playSounds else { return }
        let sound = loaded[moment] ?? Bundle.main.url(forResource: moment.rawValue, withExtension: "caf")
            .flatMap { NSSound(contentsOf: $0, byReference: true) }
        guard let sound else { return }
        loaded[moment] = sound
        if sound.isPlaying { sound.stop() }
        sound.play()
    }
}

