import AppKit
import SwiftUI

/// ⌘V in the main window, when nothing is being typed into, opens Add Item with what's on the clipboard.
/// A paste into a text field still goes to the field: the monitor only acts when the window's first
/// responder isn't text, and only in the window it's attached to (not Settings or Quick Access).
struct PasteToAdd: NSViewRepresentable {
    let paste: (String) -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.paste = paste
        context.coordinator.start()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.paste = paste }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.stop() }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var view: NSView?
        var paste: ((String) -> Bool)?
        private var monitor: Any?

        func start() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.view?.window, event.window === window,
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                      event.charactersIgnoringModifiers?.lowercased() == "v" else { return event }
                // Typing somewhere: let the field have it.
                if window.firstResponder is NSText { return event }
                guard let text = NSPasteboard.general.string(forType: .string),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return event }
                return self.paste?(text) == true ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
