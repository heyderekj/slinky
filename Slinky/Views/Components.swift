import SlinkyCoreShared
import SwiftUI

/// Provider initials on a soft tinted square. No brand logos, no network.
struct Monogram: View {
    var text: String
    var size: CGFloat = 30

    private var initials: String {
        let letters = text.filter { $0.isLetter || $0.isNumber }
        return String(letters.prefix(2)).capitalized
    }

    private var hue: Double {
        let sum = text.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Double(sum % 360) / 360
    }

    var body: some View {
        Text(initials.isEmpty ? "•" : initials)
            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
            .foregroundStyle(Color(hue: hue, saturation: 0.45, brightness: 0.45))
            .frame(width: size, height: size)
            .background(Color(hue: hue, saturation: 0.25, brightness: 0.96), in: .rect(cornerRadius: size * 0.27))
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
                Text("hover to peek").font(.caption2).foregroundStyle(.tertiary)
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
                Image(systemName: "checkmark").foregroundStyle(.tint)
                Text(toast.text).font(.callout)
                if toast.canUndo {
                    Button("Undo") { model.undo() }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .padding(.bottom, 22)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(toast.id)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: toast.id)
        }
    }
}

/// The app icon, drawn in SwiftUI for in-app use (welcome and lock screens).
struct KeyholeMark: View {
    var size: CGFloat = 96

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.97, green: 0.99, blue: 1), Color(red: 0.84, green: 0.91, blue: 0.96)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            AsteriskShape()
                .stroke(Color.white, style: StrokeStyle(lineWidth: size * 0.146, lineCap: .round))
                .shadow(color: Color(red: 0.31, green: 0.46, blue: 0.6).opacity(0.35), radius: size * 0.04, x: size * 0.012, y: size * 0.018)
                .rotationEffect(.degrees(-8))
                .padding(size * 0.21)
            Capsule()
                .fill(LinearGradient(colors: [Color(red: 0.12, green: 0.25, blue: 0.37), Color(red: 0.31, green: 0.5, blue: 0.66)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.053, height: size * 0.15)
                .offset(y: size * 0.03)
                .overlay(Circle()
                    .fill(Color(red: 0.12, green: 0.25, blue: 0.37))
                    .frame(width: size * 0.12)
                    .offset(y: -size * 0.07))
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
