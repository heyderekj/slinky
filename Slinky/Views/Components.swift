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
        .shadow(color: bottom.opacity(0.35), radius: size * 0.1, y: size * 0.05)
        .accessibilityHidden(true)
    }
}

enum ChipStyle { case live, test, plain, warn, accent }

struct Chip: View {
    var text: String
    var style: ChipStyle

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.4)
            .lineLimit(1)
            .fixedSize()   // a status never wraps; the name beside it gives way instead
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(foreground)
            .background(background, in: .rect(cornerRadius: 5))
    }

    private var foreground: Color {
        switch style {
        case .live: .red
        case .test, .accent: .accentColor
        case .plain: .secondary
        case .warn: .orange
        }
    }

    private var background: Color {
        switch style {
        case .plain: Color.secondary.opacity(0.1)
        default: foreground.opacity(0.12)
        }
    }
}

/// Dots by default, the real value while the pointer is over it (like Apple Passwords).
struct RevealField: View {
    var value: String
    var mono = true
    @State private var revealed = false

    var body: some View {
        HStack(spacing: 8) {
            Text(revealed ? value : Peek.of(value))
                .font(.system(size: 12.5, design: mono ? .monospaced : .default))
                .textSelection(.enabled)
                .lineLimit(revealed ? 4 : 1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if !revealed {
                Text("Hover to show").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.background.secondary, in: .rect(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
        .onHover { revealed = $0 }
        .accessibilityLabel("Hidden value, ends in \(String(value.suffix(4)))")
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let toast = model.toast {
            HStack(spacing: 10) {
                Image(systemName: symbol(toast.style))
                    .foregroundStyle(toast.style == .success ? Color.green : Color.secondary)
                Text(toast.text).font(.callout)
                if toast.canUndo {
                    Button("Undo") { model.undo() }
                        .glassButton()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glass(in: .capsule)
            .padding(.bottom, 22)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(toast.id)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: toast.id)
        }
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
        .shadow(color: .black.opacity(0.12), radius: size * 0.08, y: size * 0.05)
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

    var body: some View {
        Button {
            action()
            copied = true
            Task { try? await Task.sleep(for: .seconds(1.4)); copied = false }
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copied ? Color.green : Color.primary)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
    }
}

/// "1 variable", "1,284 variables". Plain English plurals for counts shown to people.
func counted(_ n: Int, _ one: String, _ many: String? = nil) -> String {
    "\(n.formatted()) \(n == 1 ? one : many ?? one + "s")"
}
