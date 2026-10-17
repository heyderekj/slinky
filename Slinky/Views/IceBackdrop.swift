import AppKit
import SwiftUI

/// The Slinky ground: pale ice with a soft light from the upper left (smoky slate in dark mode).
/// Used behind full-window moments and the Library shelf, so glass has something to catch.
struct IceBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var intensity: Double = 1

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            LinearGradient(
                colors: dark ? [Color(red: 0.10, green: 0.13, blue: 0.16), Color(red: 0.03, green: 0.04, blue: 0.05)]
                             : [Color(red: 0.97, green: 0.985, blue: 1.0), Color(red: 0.85, green: 0.91, blue: 0.955)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [dark ? Color(red: 0.36, green: 0.45, blue: 0.53).opacity(0.35) : .white.opacity(0.95), .clear],
                           center: UnitPoint(x: 0.15, y: 0.05), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Color(red: 0.53, green: 0.72, blue: 0.86).opacity(dark ? 0.16 : 0.35), .clear],
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
            ? NSColor(red: 0.085, green: 0.095, blue: 0.11, alpha: 1)
            : NSColor(red: 0.985, green: 0.99, blue: 1.0, alpha: 1)
    }) }

    /// Text on an accent-colored highlight. White on the deep light-mode accent (about 4.6:1);
    /// deep navy on the pale dark-mode accent (about 10:1). White there was only 1.8:1.
    static var onAccent: Color { Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.055, green: 0.133, blue: 0.2, alpha: 1)
            : .white
    }) }
}

/// A gentle float for the mark on welcome and lock screens. Off with Reduce Motion.
struct Floating: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .offset(y: up ? -4 : 4)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) { up = true }
            }
    }
}

extension View {
    func floating() -> some View { modifier(Floating()) }

}
