import AppIntents
import notify
import SwiftUI
import WidgetKit

// A Control Center and menu bar control (macOS 26 and later) that locks Slinky. It runs in this small sandboxed
// extension, which knows nothing about the vault: it only tells Slinky to lock. Anything on the Mac could send
// the same signal, and all it can do is lock.

@main
struct SlinkyControls: WidgetBundle {
    var body: some Widget {
        LockControl()
    }
}

struct LockControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.slinky.app.controls.lock") {
            ControlWidgetButton(action: LockSlinkyControlIntent()) {
                Label("Lock Slinky", systemImage: "lock.fill")
            }
        }
        .displayName("Lock Slinky")
        .description("Locks Slinky right away.")
    }
}

struct LockSlinkyControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Lock Slinky"
    static let description = IntentDescription("Locks Slinky right away.")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        notify_post("com.slinky.app.lock")
        return .result()
    }
}
