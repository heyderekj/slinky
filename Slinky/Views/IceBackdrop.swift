import AppKit
import SwiftUI

/// The Slinky ground: pale glacier ice with a soft light from the upper left (smoky slate in dark mode).
/// Used behind full-window moments and the Library shelf, so glass has something to catch.
struct IceBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var intensity: Double = 1

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            LinearGradient(
                colors: dark ? [Color(red: 0.09, green: 0.135, blue: 0.15), Color(red: 0.03, green: 0.045, blue: 0.05)]
                             : [Color(red: 0.965, green: 0.99, blue: 0.995), Color(red: 0.84, green: 0.93, blue: 0.945)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [dark ? Color(red: 0.32, green: 0.47, blue: 0.51).opacity(0.35) : .white.opacity(0.95), .clear],
                           center: UnitPoint(x: 0.15, y: 0.05), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Color(red: 0.45, green: 0.80, blue: 0.86).opacity(dark ? 0.16 : 0.35), .clear],
                           center: UnitPoint(x: 0.9, y: 1.0), startRadius: 0, endRadius: 560)
        }
        .opacity(intensity)
        .ignoresSafeArea()
    }
}

/// The window's ground: the desktop shows through, blurred (behind-window vibrancy), with a light ice tint.
/// macOS turns it solid on its own when Reduce Transparency is on.
struct WindowGlass: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            BehindWindowBlur()
            IceBackdrop(intensity: scheme == .dark ? 0.45 : 0.4)
        }
        .ignoresSafeArea()
    }
}

private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Opaque "paper" under values, slightly cool so white-on-white never washes out.
extension ShapeStyle where Self == Color {
    static var paper: Color { Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.08, green: 0.098, blue: 0.105, alpha: 1)
            : NSColor(red: 0.983, green: 0.993, blue: 0.997, alpha: 1)
    }) }

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
