import SlinkyCoreShared
import SwiftUI

/// Initials on a soft tinted square: the last fallback for ServiceIcon when there is no app icon or logo.
/// A small Mac-app-icon tile for a service, project or account: a continuous squircle with a vibrant gradient,
/// a soft top sheen, a hairline rim and a white letter. Colors come from a short curated palette that sits
/// well next to Slinky's glacier cyan. With no name yet, it shows Slinky's own asterisk on glacier cyan.
struct Monogram: View {
    var text: String
    var size: CGFloat = 30

    /// (top, bottom) gradient stops. Glacier first: it's Slinky's own color.
    private static let palette: [(Color, Color)] = [
        (Color(red: 0.50, green: 0.89, blue: 0.95), Color(red: 0.04, green: 0.56, blue: 0.66)),   // glacier cyan
        (Color(red: 0.55, green: 0.76, blue: 0.98), Color(red: 0.16, green: 0.42, blue: 0.84)),   // sky
        (Color(red: 0.56, green: 0.92, blue: 0.66), Color(red: 0.12, green: 0.62, blue: 0.40)),   // mint
        (Color(red: 0.62, green: 0.66, blue: 1.00), Color(red: 0.30, green: 0.30, blue: 0.86)),   // indigo
        (Color(red: 0.80, green: 0.64, blue: 1.00), Color(red: 0.50, green: 0.28, blue: 0.86)),   // violet
        (Color(red: 1.00, green: 0.64, blue: 0.80), Color(red: 0.86, green: 0.28, blue: 0.54)),   // pink
        (Color(red: 1.00, green: 0.70, blue: 0.56), Color(red: 0.92, green: 0.36, blue: 0.28)),   // coral
        (Color(red: 1.00, green: 0.84, blue: 0.46), Color(red: 0.94, green: 0.56, blue: 0.14)),   // amber
    ]

    private var trimmed: String { text.trimmingCharacters(in: .whitespaces) }

    /// "GITHUB_TOKEN" → "GT", "Slinky" → "S", "Apple Account" → "AA".
    private var initials: String {
        let words = trimmed.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.count >= 2 { return String(words.prefix(2).compactMap(\.first)).uppercased() }
        return trimmed.first.map { String($0).uppercased() } ?? ""
    }

    private var colors: (Color, Color) {
        guard !initials.isEmpty else { return Self.palette[0] }
        let sum = trimmed.lowercased().unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Self.palette[sum % Self.palette.count]
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        let (top, bottom) = colors
        ZStack {
            shape.fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
            // The sheen: light from above, like the app icon.
            shape.fill(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0)], startPoint: .top, endPoint: .center))
            if initials.isEmpty {
                AsteriskShape()
                    .stroke(Color.white, style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round))
                    .frame(width: size * 0.56, height: size * 0.56)
                    .rotationEffect(.degrees(-8))
            } else {
                Text(initials)
                    .font(.system(size: size * (initials.count > 1 ? 0.38 : 0.48), weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: size * 0.02, y: size * 0.02)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(width: size, height: size)
        .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .black.opacity(0.12)], startPoint: .top, endPoint: .bottom),
                                    lineWidth: max(0.5, size * 0.02)))
        // A small neutral shadow, like the logo tiles: no colored glow.
        .shadow(color: .black.opacity(0.1), radius: size * 0.03, y: size * 0.02)
        .accessibilityHidden(true)
    }
}

enum ChipStyle { case live, test, plain, warn, accent }

struct Chip: View {
    var text: String
    var style: ChipStyle
    /// `.increased` on a selected (highlighted) row: colored text on the cyan highlight is hard to read, so the
    /// chip turns white there, like the row's own text.
    @Environment(\.backgroundProminence) private var prominence
    private var onHighlight: Bool { prominence == .increased }

    var body: some View {
        // Sentence case in a capsule, the way Tahoe marks status (not tiny capitals in a box).
        Text(text.prefix(1).uppercased() + text.dropFirst())
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .fixedSize()   // a status never wraps; the name beside it gives way instead
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(foreground)
            .background(background, in: .capsule)
    }

    private var foreground: Color {
        if onHighlight { return .white }
        return switch style {
        case .live: .danger
        case .test, .accent: .accentColor
        case .plain: .secondary
        case .warn: .attention
        }
    }

    private var background: Color {
        if onHighlight { return Color.white.opacity(0.2) }
        return switch style {
        case .plain: Color.secondary.opacity(0.1)
        default: foreground.opacity(0.12)
        }
    }
}

/// Dots by default, the real value while the pointer is over it (like Apple Passwords), or while it has keyboard
/// focus, so it works without a mouse too. Return shows the whole value.
struct RevealField: View {
    var value: String
    var mono = true
    @State private var hovering = false
    @FocusState private var focused: Bool
    @State private var showAll = false
    private var revealed: Bool { hovering || focused }

    var body: some View {
        HStack(spacing: 8) {
            // Always one line, so hovering never moves what's below it. The whole value is one click away.
            Text(revealed ? value : Peek.of(value))
                .font(mono ? .callout.monospaced() : .callout)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if revealed {
                Button { showAll = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").imageScale(.small).fontWeight(.semibold)
                }
                .buttonStyle(.borderless)
                .help("Show the whole value")
                .accessibilityLabel("Show the whole value")
            } else {
                Text("Hover to show").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        // Values sit on paper. No outline: inside a grouped form row, a box in a box.
        .background(Color.paper, in: .rect(cornerRadius: 9))
        .onHover { hovering = $0 }
        .focusable()
        .focused($focused)
        .onKeyPress(.return) { showAll = true; return .handled }
        .accessibilityAction(named: "Show the whole value") { showAll = true }
        .popover(isPresented: $showAll, arrowEdge: .bottom) {
            ScrollView {
                Text(value)
                    .font(mono ? .callout.monospaced() : .callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .frame(width: 420)
            .frame(maxHeight: 260)
        }
        // The same peek sighted people get: never the end of a value too short to hide it.
        .accessibilityLabel(Peek.of(value).hasPrefix("••••••••") ? "Hidden value" : "Hidden value, ends in \(String(value.suffix(4)))")
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The animation lives outside the `if`, so toasts actually slide in and out (inside it, they just appeared).
        ZStack {
            if let toast = model.toast { pill(toast) }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.32), value: model.toast?.id)
    }

    private func pill(_ toast: Toast) -> some View {
        Group {
            HStack(spacing: 10) {
                Image(systemName: symbol(toast.style))
                    .foregroundStyle(toast.style == .success ? Color.done : Color.secondary)
                Text(toast.text).font(.callout)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if toast.canUndo {
                    Button("Undo") { model.undo() }
                        .glassButton()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: 560)
            // A pill for one line; when a long name makes it two, the ends stay round without ballooning.
            .glass(in: .rect(cornerRadius: 19, style: .continuous))
            .padding(.horizontal, 24)
            .padding(.bottom, 22)
        }
        .transition(reduceMotion ? .opacity : .offset(y: 18).combined(with: .opacity))
        .id(toast.id)
    }

    private func symbol(_ style: Toast.Style) -> String {
        switch style {
        case .success: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .removed: "trash.circle.fill"
        }
    }
}

/// The app icon, drawn in SwiftUI. `keyholeScale` and `spin` drive the "working" animation:
/// the keyhole is absorbed into the asterisk, which turns, then the keyhole returns.
struct KeyholeMark: View {
    var size: CGFloat = 96
    var keyholeScale: CGFloat = 1
    var spin: Double = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.52, green: 0.89, blue: 0.95), Color(red: 0.06, green: 0.62, blue: 0.72)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            // Only the asterisk turns. The keyhole always stays upright.
            AsteriskShape()
                .stroke(Color.white, style: StrokeStyle(lineWidth: size * 0.146, lineCap: .round))
                .shadow(color: Color(red: 0.02, green: 0.22, blue: 0.27).opacity(0.45), radius: size * 0.04, x: size * 0.012, y: size * 0.018)
                .padding(size * 0.21)
                .rotationEffect(.degrees(-8 + spin))
            ZStack {
                Capsule()
                    .fill(LinearGradient(colors: [Color(red: 0.03, green: 0.16, blue: 0.19), Color(red: 0.07, green: 0.31, blue: 0.36)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.053, height: size * 0.15)
                    .offset(y: size * 0.03)
                    .overlay(Circle()
                        .fill(Color(red: 0.03, green: 0.16, blue: 0.19))
                        .frame(width: size * 0.12)
                        .offset(y: -size * 0.07))
                    .scaleEffect(keyholeScale)
                    .opacity(Double(keyholeScale))
            }
            .rotationEffect(.degrees(-8))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.1), radius: size * 0.03, y: size * 0.02)
        .accessibilityHidden(true)
    }
}

struct AsteriskShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        for i in 0..<3 {
            let a = Double(90 + i * 60) * .pi / 180
            p.move(to: CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)))
            p.addLine(to: CGPoint(x: c.x - r * cos(a), y: c.y - r * sin(a)))
        }
        return p
    }
}

/// Copy with an SF Symbol swap to a checkmark, so the click is acknowledged in place.
struct CopyButton: View {
    var title = "Copy"
    let action: () -> Void
    @State private var copied = false
    /// On a selected (accent) row everything is white, the check included: cyan on cyan disappears.
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        Button {
            action()
            withAnimation(.smooth(duration: 0.25)) { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                withAnimation(.smooth(duration: 0.25)) { copied = false }
            }
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(prominence == .increased ? Color.onAccent : copied ? Color.done : Color.primary)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
    }
}

/// "1 variable", "1,284 variables". Plain English plurals for counts shown to people.
func counted(_ n: Int, _ one: String, _ many: String? = nil) -> String {
    "\(n.formatted()) \(n == 1 ? one : many ?? one + "s")"
}

/// How long the things people type can be. Generous, but not unbounded: past these, rows, headers and menus stop
/// being readable, and nothing real is longer. Values (the secrets themselves) aren't limited here.
enum FieldLimit {
    static let name = 200
    static let note = 2_000
    static let link = 2_048
}

extension View {
    /// Keeps a text field to `max` characters as it's typed or pasted.
    func limit(_ text: Binding<String>, to max: Int) -> some View {
        onChange(of: text.wrappedValue) { _, new in
            if new.count > max { text.wrappedValue = String(new.prefix(max)) }
        }
    }
}

/// The app icon's mark, which turns one step (it looks the same after 60°): the keyhole is absorbed, the asterisk
/// turns, the keyhole returns. Once on appear (a vault was just made), or on click (a small touch in About).
/// Still with Reduce Motion.
struct TurningMark: View {
    var size: CGFloat
    var onAppear = false
    var onClick = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var keyhole: CGFloat = 1
    @State private var spin: Double = 0
    @State private var turning = false

    var body: some View {
        KeyholeMark(size: size, keyholeScale: keyhole, spin: spin)
            .contentShape(.rect)
            .onTapGesture { if onClick { turn() } }
            .task {
                guard onAppear else { return }
                try? await Task.sleep(for: .milliseconds(450))
                turn()
            }
            .accessibilityHidden(true)
    }

    private func turn() {
        guard !reduceMotion, !turning else { return }
        turning = true
        Task {
            withAnimation(.easeIn(duration: 0.22)) { keyhole = 0 }
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) { spin += 60 }
            try? await Task.sleep(for: .milliseconds(480))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { keyhole = 1 }
            try? await Task.sleep(for: .milliseconds(400))
            turning = false
        }
    }
}

/// A tiny .env, to show what a project holds. With `masks`, the example values turn into dots left to right once,
/// the same move Add Item makes with a pasted value; with Reduce Motion they're dots from the start.
/// The values are made-up examples, never anything from the vault.
struct EnvPreview: View {
    var masks = false
    var fontSize: CGFloat = 10.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var masked: [Int] = [0, 0, 0]

    private static let lines = [("DATABASE_URL", "postgres://local"), ("STRIPE_SECRET_KEY", "sk_test_EXAMPLE"), ("OPENAI_API_KEY", "sk-proj-EXAMPLE")]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(Self.lines.enumerated()), id: \.offset) { i, line in
                HStack(spacing: 0) {
                    Text(line.0).foregroundStyle(.secondary)
                    Text("=" + shown(line.1, masked: masks ? masked[i] : .max)).foregroundStyle(.tertiary)
                }
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                .lineLimit(1)
            }
        }
        .task {
            guard masks else { return }
            if reduceMotion { masked = Self.lines.map(\.1.count); return }
            try? await Task.sleep(for: .milliseconds(500))
            for i in Self.lines.indices {
                for n in 1...Self.lines[i].1.count {
                    masked[i] = n
                    try? await Task.sleep(for: .milliseconds(22))
                }
                try? await Task.sleep(for: .milliseconds(90))
            }
        }
    }

    /// The first `masked` characters as dots, the rest as typed; fully masked shows four dots, like a saved value.
    private func shown(_ value: String, masked: Int) -> String {
        if masked >= value.count { return "••••" }
        return String(repeating: "•", count: masked) + value.dropFirst(masked)
    }
}

/// The ✕ at the top right of a floating panel. Same as Cancel and esc; a glass circle on Tahoe.
struct PanelCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Close", systemImage: "xmark")
                .labelStyle(.iconOnly)
                .fontWeight(.semibold)
        }
        .glassButton()
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .help("Close (esc)")
    }
}

extension View {
    /// A floating panel coming in: it rises a little and grows into place. With Reduce Motion it only fades.
    func panelEntrance(_ appeared: Bool) -> some View {
        modifier(PanelEntrance(appeared: appeared))
    }
}

private struct PanelEntrance: ViewModifier {
    let appeared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(appeared || reduceMotion ? 1 : 0.95)
            .offset(y: appeared || reduceMotion ? 0 : 14)
            .opacity(appeared ? 1 : 0)
    }
}

extension View {
    /// A card on the content surface: a soft gray fill, no outline, like Passwords' tiles. Content, so not glass.
    func card(cornerRadius: CGFloat) -> some View {
        background(Color.primary.opacity(0.045), in: .rect(cornerRadius: cornerRadius, style: .continuous))
    }
}
