import Foundation
import SlinkyCoreShared
import UserNotifications

/// Mac notifications, only if the person turned them on (Settings › General). Names only: never a value.
@MainActor
enum Reminders {
    private static var enabled: Bool { Preferences.shared.reminders }
    private static let expiryPrefix = "slinky.expiry."

    /// Asks macOS once, when the setting is turned on.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func leaksFound(_ names: [String]) {
        guard enabled, !names.isEmpty else { return }
        let unique = Array(Set(names)).sorted()
        post("leak.\(UUID().uuidString)", title: "Found outside Slinky",
             body: unique.count == 1 ? "\(unique[0]) is written somewhere it shouldn't be. Open Health to see where."
                                     : "\(unique.count) saved secrets are written somewhere they shouldn't be. Open Health to see where.")
    }

    static func codesLow(account: String, left: Int) {
        guard enabled else { return }
        post("codes.\(account)", title: left == 0 ? "No \(account) codes left" : "\(left) \(account) codes left",
             body: "Make new recovery codes on \(account), then add them to Slinky.")
    }

    /// Reminders for keys with an expiry date: a week before and the day before, at 9 in the morning.
    /// Rebuilt whenever the vault changes while unlocked, so they keep working after Slinky locks.
    static func schedule(_ document: VaultDocument) {
        let center = UNUserNotificationCenter.current()
        Task {
            let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(expiryPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: pending)
            guard enabled else { return }
            for key in document.keys {
                guard let expires = key.expires, expires > .now else { continue }
                for (days, when) in [(7, "in a week"), (1, "tomorrow")] {
                    guard let date = Calendar.current.date(byAdding: .day, value: -days, to: expires), date > .now else { continue }
                    var parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
                    parts.hour = 9
                    let content = UNMutableNotificationContent()
                    content.title = "\(key.name) expires \(when)"
                    content.body = "Make a new one, then replace it in Slinky."
                    let request = UNNotificationRequest(identifier: "\(expiryPrefix)\(key.id).\(days)", content: content,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
                    try? await center.add(request)
                }
            }
        }
    }

    private static func post(_ id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
