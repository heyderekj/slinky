import AppKit

/// Copies secrets the careful way:
/// - marked concealed and transient (nspasteboard.org), so clipboard managers and history skip them
/// - kept off Universal Clipboard
/// - cleared after 60 seconds, but only if nothing else was copied since
enum Clipboard {
    private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static let source = NSPasteboard.PasteboardType("org.nspasteboard.source")

    static func copy(_ value: String, clearAfter seconds: Double = 60) {
        let board = NSPasteboard.general
        board.prepareForNewContents(with: .currentHostOnly)
        let item = NSPasteboardItem()
        item.setString(value, forType: .string)
        item.setString("", forType: concealed)
        item.setString("", forType: transient)
        item.setString("com.slinky.app", forType: source)
        board.writeObjects([item])
        let stamp = board.changeCount
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if board.changeCount == stamp { board.clearContents() }
        }
    }
}
