import SwiftUI

/// The empty-state story (Slinky's sibling to Dinky's IdleAnimation):
/// each secret rises from the bottom edge, its characters turn into dots, it slides into the icon,
/// the keyhole closes, the asterisk turns, and the keyhole returns with a green checkmark.
/// It ends like Dinky does: on a resting collection of examples, fanned under the icon.
/// Hover replays it. Under Reduce Motion, only the resting collection shows.
struct VaultIdleAnimation: View {
    struct Sample: Equatable {
        let symbol: String
        let label: String
        let value: String
        /// How the item reads once it's stored.
        let rest: String
        /// Where it rests in the smile (see `fan`).
        let slot: Int
    }

    var samples: [Sample] = VaultIdleAnimation.defaultSamples

    /// Everything Slinky holds: a key, a project's .env line, recovery codes and a recovery key.
    static let defaultSamples = [
        Sample(symbol: "key.fill", label: "API key", value: "sk_live_51H8xQ2Lm4f2a", rest: "sk_live_…4f2a", slot: 0),
        Sample(symbol: "folder.fill", label: "Project variable", value: "RESEND_API_KEY=re_8Kd2Lq9w", rest: "RESEND_API_KEY=••••", slot: 1),
        Sample(symbol: "number.square.fill", label: "Recovery codes", value: "a1b2c-3d4e5  f6a7b-8c9d0", rest: "10 codes", slot: 3),
        Sample(symbol: "lifepreserver.fill", label: "Recovery key", value: "R7KQ-2MXP-9TDV-4HCE", rest: "R7KQ-••••-••••", slot: 2),
    ]

    private static let iconY: CGFloat = -50
    /// A smile under the icon (the icon is the nose), made of the same pills that play the story.
    /// The inner pair sits low and centered as a pair; the outer pills sit higher and reach the same
    /// distance past it on each side. Pills stay level: rotated glass draws oversized.
    /// Slots: 0 outer left, 1 inner left, 2 inner right, 3 outer right.
    private static let innerY: CGFloat = 80
    private static let outerY: CGFloat = 26
    private static let innerGap: CGFloat = 7
    private static let outerReach: CGFloat = 40

    private func restCenter(_ slot: Int) -> CGSize {
        let w = widths
        let shift = (w[1] - w[2]) / 2
        let half = (w[1] + w[2]) / 2 + Self.innerGap
        switch slot {
        case 0: return CGSize(width: -(half + Self.outerReach) + w[0] / 2, height: Self.outerY)
        case 1: return CGSize(width: shift - Self.innerGap - w[1] / 2, height: Self.innerY)
        case 2: return CGSize(width: shift + Self.innerGap + w[2] / 2, height: Self.innerY)
        default: return CGSize(width: half + Self.outerReach - w[3] / 2, height: Self.outerY)
        }
    }

    /// Inner pills draw on top; the inner pair comes out first, then the ends.
    private static let drawOrder = [0, 3, 1, 2]
    private static let revealOrder = [1, 2, 0, 3]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var runID = UUID()
    @State private var finished = false
    @State private var index = 0
    @State private var masked = 0
    @State private var cardOffset = CGSize(width: 0, height: 260)
    @State private var cardScale: CGFloat = 1
    @State private var cardOpacity: Double = 0
    @State private var keyholeScale: CGFloat = 1
    @State private var spin: Double = 0
    @State private var showCheck = false
    @State private var checkFade = false
    @State private var restShown: [Bool] = Array(repeating: false, count: 4)
    /// Measured pill widths by slot, so the smile stays symmetric whatever the text.
    @State private var widths: [CGFloat] = Array(repeating: 160, count: 4)

    private var sample: Sample { samples[index % samples.count] }

    var body: some View {
        ZStack {
            // The resting collection, drawn behind the moving pill.
            ForEach(Self.drawOrder, id: \.self) { slot in
                if let i = samples.firstIndex(where: { $0.slot == slot }) {
                    pill(samples[i], text: samples[i].rest)
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { widths[slot] = $0 }
                        .scaleEffect(restShown[i] ? 1 : 0.4)
                        .offset(restShown[i] ? restCenter(slot) : CGSize(width: 0, height: Self.iconY))
                        .opacity(restShown[i] ? 1 : 0)
                }
            }
            KeyholeMark(size: 92, keyholeScale: keyholeScale, spin: spin)
                .overlay(alignment: .bottomTrailing) {
                    if showCheck {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 26))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.green)
                            .offset(x: 10, y: 10)
                            .scaleEffect(checkFade ? 0.5 : 1)
                            .opacity(checkFade ? 0 : 1)
                            .transition(.symbolEffect(.drawOn))
                    }
                }
                .offset(y: Self.iconY)
            movingCard
                .scaleEffect(cardScale)
                .offset(cardOffset)
                .opacity(cardOpacity)
        }
        .frame(width: 580, height: 280)
        .clipped()
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering, finished {
                finished = false
                runID = UUID()
            }
        }
        .task(id: runID) { await play() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Examples of what Slinky stores: an API key, a project variable, recovery codes and a recovery key")
    }

    private var movingCard: some View {
        pill(sample, text: display, animated: true)
    }

    /// The one pill shape used for both the story and the resting collection.
    private func pill(_ s: Sample, text: String, animated: Bool = false) -> some View {
        HStack(spacing: 9) {
            Image(systemName: s.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(s.label).font(.caption2).foregroundStyle(.secondary)
                Text(text)
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .contentTransition(.interpolate)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .fixedSize()
        .glassEffect(.regular, in: .capsule)
    }

    /// Characters turn into dots from left to right; separators stay so the shape still reads.
    /// For a KEY=value line, only the value is hidden. The name isn't a secret.
    private var display: String {
        var out = ""
        var count = 0
        var inValue = !sample.value.contains("=")
        for ch in sample.value {
            if !inValue { out.append(ch); if ch == "=" { inValue = true }; continue }
            if Self.isSeparator(ch) { out.append(ch); continue }
            out.append(count < masked ? "•" : ch)
            count += 1
        }
        return out
    }

    private static func isSeparator(_ ch: Character) -> Bool { ch == "-" || ch == "_" || ch == " " }

    private static func maskable(_ value: String) -> Int {
        let secret = value.split(separator: "=", maxSplits: 1).last.map(String.init) ?? value
        return secret.filter { !isSeparator($0) }.count
    }

    private func play() async {
        if reduceMotion {
            restShown = restShown.map { _ in true }
            finished = true
            return
        }
        // Tuck the collection back into the icon before replaying.
        withAnimation(.easeIn(duration: 0.3)) { restShown = restShown.map { _ in false } }
        try? await Task.sleep(for: .milliseconds(450))
        for i in samples.indices {
            guard !Task.isCancelled else { return }
            await playOne(i)
        }
        // Rest like Dinky: the examples slide back out as a collection.
        for i in Self.revealOrder where samples.indices.contains(i) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) { restShown[i] = true }
            try? await Task.sleep(for: .milliseconds(110))
        }
        finished = true
    }

    private func playOne(_ i: Int) async {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            index = i
            masked = 0
            cardScale = 1
            cardOpacity = 1
            cardOffset = CGSize(width: i.isMultiple(of: 2) ? -120 : 120, height: 220)
        }
        // Rise into view below the icon.
        withAnimation(.spring(response: 0.85, dampingFraction: 0.82)) { cardOffset = CGSize(width: 0, height: 64) }
        try? await Task.sleep(for: .milliseconds(750))

        // Mask, one character at a time.
        let total = Self.maskable(sample.value)
        for n in 1...total {
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.12)) { masked = n }
            try? await Task.sleep(for: .milliseconds(32))
        }
        try? await Task.sleep(for: .milliseconds(250))

        // Slide into the icon; the keyhole is absorbed.
        withAnimation(.easeIn(duration: 0.42)) {
            cardOffset = CGSize(width: 0, height: Self.iconY)
            cardScale = 0.15
            cardOpacity = 0
            keyholeScale = 0
        }
        try? await Task.sleep(for: .milliseconds(380))

        // The asterisk turns one step (it looks the same after 60°); the upright keyhole returns.
        withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) { spin += 60 }
        try? await Task.sleep(for: .milliseconds(520))
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { keyholeScale = 1 }
        withAnimation(.easeOut(duration: 0.2)) { showCheck = true }
        try? await Task.sleep(for: .milliseconds(850))
        // Exit: shrink and fade, then remove without replaying the draw in reverse.
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { checkFade = true }
        try? await Task.sleep(for: .milliseconds(300))
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            showCheck = false
            checkFade = false
        }
        try? await Task.sleep(for: .milliseconds(220))
    }
}
