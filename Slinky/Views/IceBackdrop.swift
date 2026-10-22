import AppKit
import SwiftUI

/// Opaque "paper" under values, slightly cool so white-on-white never washes out.
extension ShapeStyle where Self == Color {
    static var paper: Color { Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.08, green: 0.098, blue: 0.105, alpha: 1)
            : NSColor(red: 0.983, green: 0.993, blue: 0.997, alpha: 1)
    }) }

    /// The content's ground, like Passwords and Mail: solid white (near-black in dark mode), the same surface an
    /// inset list paints, so every screen matches. Only chrome is glass: the sidebar, toolbar, details pane, panels.
    static var surface: Color { Color(nsColor: .controlBackgroundColor) }

    /// Text on an accent-colored highlight. White in both modes: the accent (#0b7f8f glacier cyan, light and
    /// dark) is deep enough for it, about 4.7:1. The old pale dark-mode accent wasn't.
    static var onAccent: Color { .white }

    // Status colors. Calm on purpose: amber only where something needs a person, the brand's cyan for done.
    // (DESIGN.md › Color. Not system orange or green, which read as a default UI.)

    /// Something needs you: an expiring key, low codes, a key left in a file. A calm amber, not system orange.
    static var attention: Color { Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.886, green: 0.710, blue: 0.396, alpha: 1)   // #E2B565
            : NSColor(red: 0.722, green: 0.525, blue: 0.180, alpha: 1)   // #B8862E
    }) }

    /// Done, all clear, used: the glacier cyan accent.
    static var done: Color { .accentColor }

    /// Live keys, deleting, errors. Rare, so it can stay plain red.
    static var danger: Color { .red }
}
