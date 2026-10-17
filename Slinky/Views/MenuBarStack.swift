import AppKit
import SlinkyCoreShared
import SwiftUI

/// The menu bar menu: a header with status and a lock toggle, then native-feeling rows.
struct MenuBarStack: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.horizontal, 12)
            VStack(spacing: 2) {
                MenuRow(icon: "magnifyingglass", title: "Quick Access", shortcut: "⌥⌘K") {
                    QuickAccess.shared.show()
                }
                MenuRow(icon: "plus", title: "Add Item…", shortcut: "⌘N", disabled: !model.isUnlocked) {
                    open()
                    model.openAddItem()
                }
            }
            .padding(6)
            if model.isUnlocked, !model.recent.isEmpty {
                Divider().padding(.horizontal, 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recently Copied")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.top, 4)
                    ForEach(model.recent) { item in
                        RecentRow(item: item) { model.copy(item.value, label: item.title, provider: item.provider) }
                    }
                }
                .padding(6)
            }
            Divider().padding(.horizontal, 12)
            VStack(spacing: 2) {
                MenuRow(icon: "macwindow", title: "Open Slinky") { open() }
                MenuRow(icon: "gearshape", title: "Settings…", shortcut: "⌘,") {
                    openWindow(id: "settings")
                    NSApp.activate()
                }
                MenuRow(icon: "info.circle", title: "About Slinky") { AboutPanel.show() }
                MenuRow(icon: "power", title: "Quit Slinky", shortcut: "⌘Q") { NSApp.terminate(nil) }
            }
            .padding(6)
        }
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 10) {
            KeyholeMark(size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("Slinky").font(.headline)
                HStack(spacing: 5) {
                    Circle()
                        .fill(model.isUnlocked ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.hasVault {
                Button {
                    if model.isUnlocked { model.lockAnimated() } else { model.unlock() }
                } label: {
                    Image(systemName: model.isUnlocked ? "lock.open.fill" : "lock.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 18, height: 18)
                }
                .glassButton()
                .buttonBorderShape(.circle)
                .help(model.isUnlocked ? "Lock Slinky" : "Unlock Slinky")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var status: String {
        if !model.hasVault { return "No vault yet" }
        return model.isUnlocked ? "Unlocked" : "Locked"
    }

    private func open() {
        openWindow(id: "main")
        NSApp.activate()
    }
}

/// A row that looks and behaves like a Tahoe menu item: icon, title, shortcut, highlight on hover.
struct MenuRow: View {
    let icon: String
    let title: String
    var shortcut: String?
    var disabled = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 18)
                    .foregroundStyle(hovering ? Color.onAccent : Color.secondary)
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut).foregroundStyle(hovering ? Color.onAccent.opacity(0.75) : Color.secondary)
                }
            }
            .foregroundStyle(hovering ? Color.onAccent : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(hovering && !disabled ? Color.accentColor : .clear, in: .rect(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .onHover { hovering = $0 }
    }
}

struct RecentRow: View {
    let item: RecentItem
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ServiceIcon(subject: IconSubject(name: item.title, provider: item.provider), size: 22)
                Text(item.title)
                    .font(.system(size: 12, weight: .medium, design: item.mono ? .monospaced : .default))
                    .lineLimit(1)
                Spacer()
                if hovering {
                    Text("Copy").font(.caption).foregroundStyle(Color.onAccent.opacity(0.75))
                }
            }
            .foregroundStyle(hovering ? Color.onAccent : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(hovering ? Color.accentColor : .clear, in: .rect(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Slinky's own menu bar glyph: the asterisk with the keyhole cut out, as a template image.
enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let c = CGPoint(x: rect.midX, y: rect.midY)
            // About 12.5 × 13pt of ink, measured against the system's own items (Wi-Fi 15 × 11,
            // Spotlight 14 × 13, Control Center 12 × 12). Larger reads heavier than everything beside it.
            let r: CGFloat = 5.2
            ctx.setLineCap(.round)
            ctx.setLineWidth(2.6)
            ctx.setStrokeColor(NSColor.black.cgColor)
            for i in 0..<3 {
                let a = (CGFloat(90 + i * 60) - 8) * .pi / 180
                ctx.move(to: CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)))
                ctx.addLine(to: CGPoint(x: c.x - r * cos(a), y: c.y - r * sin(a)))
            }
            ctx.strokePath()
            // Keyhole cut-out.
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: CGRect(x: c.x - 0.93, y: c.y - 0.12, width: 1.86, height: 1.86))
            ctx.fill(CGRect(x: c.x - 0.425, y: c.y - 1.79, width: 0.85, height: 1.95))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Slinky"
        return image
    }()
}

/// The standard About panel with Dinky-style credits underneath.
enum AboutPanel {
    static func show() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 2
        let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11),
                                                   .foregroundColor: NSColor.secondaryLabelColor,
                                                   .paragraphStyle: paragraph]
        var link = base
        link.removeValue(forKey: .foregroundColor)
        let credits = NSMutableAttributedString()
        credits.append(NSAttributedString(string: "\(bundleSize()) · Made by Testament Made, LLC\n", attributes: base))
        var site = link; site[.link] = URL(string: "https://slinkyfiles.com")!
        credits.append(NSAttributedString(string: "slinkyfiles.com\n", attributes: site))
        var repo = link; repo[.link] = URL(string: "https://github.com/heyderekj/slinky")!
        credits.append(NSAttributedString(string: "github.com/heyderekj/slinky\n", attributes: repo))
        var mail = link; mail[.link] = URL(string: "mailto:derek@testamentmade.com")!
        credits.append(NSAttributedString(string: "derek@testamentmade.com", attributes: mail))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate()
    }

    /// The installed size, like Finder shows it, so "small and native" stays honest.
    private static func bundleSize() -> String {
        let url = Bundle.main.bundleURL
        var total: Int64 = 0
        if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) {
            for case let file as URL in e {
                let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
            }
        }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
}
