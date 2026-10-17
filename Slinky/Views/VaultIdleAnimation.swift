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
    }

    var samples: [Sample] = VaultIdleAnimation.defaultSamples

    /// Everything Slinky holds: a key, a project's .env line, recovery codes and a recovery key.
    static let defaultSamples = [
        Sample(symbol: "key.fill", label: "API key", value: "sk_live_51H8xQ2Lm4f2a", rest: "sk_live_…4f2a"),
        Sample(symbol: "folder.fill", label: "Project variable", value: "RESEND_API_KEY=re_8Kd2Lq9w", rest: "RESEND_API_KEY=••••"),
        Sample(symbol: "number.square.fill", label: "Recovery codes", value: "a1b2c-3d4e5  f6a7b-8c9d0", rest: "10 codes"),
        Sample(symbol: "lifepreserver.fill", label: "Recovery key", value: "R7KQ-2MXP-9TDV-4HCE", rest: "R7KQ-••••-••••"),
    ]

    private static let iconY: CGFloat = -50
    /// A smile under the icon (the icon is the nose): the ends sit higher and tilt with the curve.
    private static let fan: [(x: CGFloat, y: CGFloat, angle: Double)] = [
        (-176, 40, 13), (-62, 76, 4), (62, 76, -4), (176, 40, -13),
    ]
    /// Ends first, so the middle cards sit on top.
    private static let drawOrder = [0, 3, 1, 2]
    /// The middle comes out first, then the ends.
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

    private var sample: Sample { samples[index % samples.count] }

    var body: some View {
        ZStack {
            // The resting collection, drawn behind the moving card. Middle card on top.
            ForEach(Self.drawOrder, id: \.self) { i in
                if samples.indices.contains(i), Self.fan.indices.contains(i) {
                    restCard(samples[i])
                        .rotationEffect(.degrees(restShown[i] ? Self.fan[i].angle : 0))
                        .offset(restShown[i] ? CGSize(width: Self.fan[i].x, height: Self.fan[i].y) : CGSize(width: 0, height: Self.iconY))
                        .scaleEffect(restShown[i] ? 1 : 0.2)
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
        HStack(spacing: 10) {
            Image(systemName: sample.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.tint)
                .symbolEffect(.wiggle, value: index)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 1) {
                Text(sample.label).font(.caption).foregroundStyle(.secondary)
                Text(display)
                    .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                    .contentTransition(.interpolate)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .fixedSize()
        .glassEffect(.regular, in: .capsule)
    }

    private func restCard(_ s: Sample) -> some View {
        HStack(spacing: 9) {
            Image(systemName: s.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(s.label).font(.caption2).foregroundStyle(.secondary)
                Text(s.rest).font(.system(size: 12, weight: .medium, design: .monospaced)).lineLimit(1).fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .fixedSize()
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
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
