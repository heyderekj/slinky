import SwiftUI

/// The locked window, shared by the lock screen and the lock/unlock curtain so the two line up to the pixel.
/// The app icon is the lock: its keyhole is the way in. A ring of scrambled characters sits around it (random,
/// never anything from the vault). Unlocking turns the asterisk like a dial, scrambles the ring, then the
/// keyhole opens out until the whole window is the app.
nonisolated enum LockLayout {
    static let markSize: CGFloat = 96
    static let ringRadius: CGFloat = 82

    /// `top` is how much of `size` sits behind the toolbar (the curtain covers that strip; the lock screen doesn't),
    /// so both put the mark at the same spot in the window.
    static func markCenter(in size: CGSize, top: CGFloat = 0) -> CGPoint {
        CGPoint(x: size.width / 2, y: top + max(ringRadius + 24, (size.height - top) * 0.38))
    }

    /// The keyhole's round top, in the window, matching KeyholeMark's drawing (offset, then tilted -8°).
    static func keyholeCenter(in size: CGSize, top: CGFloat = 0) -> CGPoint {
        let c = markCenter(in: size, top: top)
        let p = rotate(CGPoint(x: 0, y: -0.04 * markSize), by: -8)
        return CGPoint(x: c.x + p.x, y: c.y + p.y)
    }

    static func rotate(_ p: CGPoint, by degrees: Double) -> CGPoint {
        let a = degrees * .pi / 180
        return CGPoint(x: p.x * cos(a) - p.y * sin(a), y: p.x * sin(a) + p.y * cos(a))
    }
}

/// The same surface as the unlocked content (an inset list's background), so locked and unlocked match in
/// light and dark. Draws nothing else.
struct LockedBackground: View {
    var body: some View {
        List {}
            .listStyle(.inset)
            .scrollDisabled(true)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The lock screen's picture and words. `controls` sits under the ring.
struct LockStage<Controls: View>: View {
    var showFace = true
    var spin: Double = 0
    /// Seconds between scrambles of the ring; nil holds it still.
    var scramble: Double?
    var ringScale: CGFloat = 1
    var top: CGFloat = 0
    @ViewBuilder var controls: Controls

    var body: some View {
        ZStack {
            LockedBackground()
            if showFace {
                GeometryReader { geo in
                    let c = LockLayout.markCenter(in: geo.size, top: top)
                    ZStack(alignment: .top) {
                        CipherRing(radius: LockLayout.ringRadius, interval: scramble)
                            .scaleEffect(ringScale)
                            .position(c)
                        KeyholeMark(size: LockLayout.markSize, spin: spin)
                            .position(c)
                        VStack(spacing: 12) { controls }
                            .frame(maxWidth: .infinity)
                            .padding(.top, c.y + LockLayout.ringRadius + 22)
                    }
                }
            }
        }
    }
}

/// What the lock screen says and offers. Static copies of it ride on the curtain.
struct LockControls: View {
    var note: String?
    var busy = false
    var error: String?
    var unlockLabel: String
    var unlock: () -> Void = {}
    var useRecoveryKey: () -> Void = {}

    var body: some View {
        Text("Slinky is locked")
            .font(.title3.weight(.semibold))
        if let note {
            Text(note).font(.callout).foregroundStyle(.secondary)
        }
        Button(action: unlock) {
            Label {
                Text(unlockLabel)
            } icon: {
                // Breathes while Touch ID is waiting for your finger (DESIGN.md: .pulse while waiting).
                Image(systemName: "touchid").symbolEffect(.pulse, options: .repeating, isActive: busy)
            }
        }
        .glassProminentButton()
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .disabled(busy)
        .padding(.top, 4)
        if let error {
            Text(error).font(.callout).foregroundStyle(Color.danger).frame(maxWidth: 380).multilineTextAlignment(.center)
        }
        Button("Use Recovery Key…", action: useRecoveryKey)
            .buttonStyle(.link)
            .font(.callout)
    }
}

/// Characters around the lock, like ciphertext. Random and meaningless: nothing here comes from the vault.
/// Still unless `interval` is set (waiting for Touch ID, or unlocking), so nothing animates at rest.
struct CipherRing: View {
    var radius: CGFloat
    var interval: Double?
    var count = 44
    @State private var seed = UInt64.random(in: 1...UInt64.max)

    private static let glyphs = Array("0123456789abcdef")

    var body: some View {
        TimelineView(.periodic(from: .now, by: interval ?? 3600)) { context in
            let tick = interval.map { UInt64(max(0, context.date.timeIntervalSinceReferenceDate / $0)) } ?? 0
            ZStack {
                ForEach(0..<count, id: \.self) { i in
                    let angle = Double(i) / Double(count) * 2 * .pi - .pi / 2
                    Text(String(glyph(i, tick)))
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .opacity(i % 4 == 0 ? 0.35 : 0.6)
                        .rotationEffect(.radians(angle + .pi / 2))
                        .offset(x: radius * cos(angle), y: radius * sin(angle))
                }
            }
            .frame(width: radius * 2 + 20, height: radius * 2 + 20)
        }
        .accessibilityHidden(true)
    }

    private func glyph(_ i: Int, _ tick: UInt64) -> Character {
        // SplitMix64 on (seed, position, tick): a fresh random-looking character per tick, no state kept.
        var z = seed &+ UInt64(i) &* 0x9E37_79B9_7F4A_7C15 &+ tick &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Self.glyphs[Int(z % 16)]
    }
}

/// The keyhole from the app icon, grown by `progress` (0 = exactly the icon's keyhole, 1 = past every corner
/// of the window, below 0 = smaller, down to a point). Growth is exponential, so it starts as a peek and ends in a rush.
nonisolated struct KeyholeHole: Shape {
    var progress: CGFloat
    var top: CGFloat = 0

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let s = LockLayout.markSize
        let center = LockLayout.keyholeCenter(in: rect.size, top: top)
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
        let far = corners.map { hypot($0.x - center.x, $0.y - center.y) }.max() ?? 1
        let radius = 0.06 * s
        let maxScale = far / radius * 1.05
        let k = pow(maxScale, min(1, progress))   // below 0 it shrinks to a point: the keyhole closed

        // The round top, joined with the slot: KeyholeMark's capsule, 0.053s wide and 0.15s tall,
        // centred 0.07s below the round top.
        let w = 0.053 * s, h = 0.15 * s
        let keyhole = Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
            .union(Path(roundedRect: CGRect(x: -w / 2, y: 0.07 * s - h / 2, width: w, height: h), cornerRadius: w / 2))
        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: -8 * .pi / 180)
            .scaledBy(x: k, y: k)
        return keyhole.applying(transform)
    }
}

extension View {
    /// The window title and subtitle for a screen, or the locked window's while Slinky locks or unlocks,
    /// so the toolbar moves with the keyhole instead of waiting for it.
    func screenTitle(_ title: String, subtitle: String) -> some View { modifier(ScreenTitle(title: title, subtitle: subtitle)) }
}

private struct ScreenTitle: ViewModifier {
    @Environment(AppModel.self) private var model
    let title: String
    let subtitle: String

    /// A long project name would widen the toolbar and squeeze the sidebar, so the title keeps its start and end
    /// ("northwind-industries-…-monorepo"); the full name is in Edit Project.
    static func short(_ title: String, max: Int = 32) -> String {
        guard title.count > max else { return title }
        let tail = max / 3
        return String(title.prefix(max - tail - 1)) + "…" + String(title.suffix(tail))
    }

    func body(content: Content) -> some View {
        content
            .navigationTitle(model.lockedChrome ? "Slinky" : Self.short(title))
            .navigationSubtitle(model.lockedChrome ? "Locked" : subtitle)
    }
}
