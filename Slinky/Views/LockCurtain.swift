import SwiftUI

/// The toolbar lock: a small switch with both states visible. The knob sits on the current one.
struct LockSwitch: View {
    @Environment(AppModel.self) private var model
    /// Inside AppKit's own glass (macOS 26, see LockSwitchAccessory), which samples the window like the toolbar's
    /// controls do. A SwiftUI glass effect in a separate title bar view had nothing to sample, so it didn't match.
    var inGlass = false

    private var locked: Bool { !model.isUnlocked || model.curtain == .closing }

    var body: some View {
        Button {
            if !model.hasVault {
                // Nothing saved yet means nothing to lock. Say so instead of doing nothing.
                model.show("Slinky can lock once you've saved your first item.", style: .info)
            } else if model.isUnlocked {
                model.lockAnimated()
            } else {
                model.unlock()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 26, height: 26)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .offset(x: locked ? 15 : -15)
                HStack(spacing: 4) {
                    icon("lock.open.fill", active: !locked)
                    icon("lock.fill", active: locked)
                }
            }
            .frame(width: 60, height: 28)
            .padding(3)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // macOS 15: a quiet capsule like the system's grouped toolbar controls, not a frosted pill.
        .background { if !inGlass { Capsule().fill(.quaternary) } }
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: locked)
        .help(!model.hasVault ? "Slinky can lock once you've saved your first item" : locked ? "Unlock Slinky" : "Lock Slinky (⌃⌘L)")
        .accessibilityLabel("Lock")
        .accessibilityValue(locked ? "Locked" : "Unlocked")
        .accessibilityHint(locked ? "Unlocks Slinky" : "Locks Slinky")
    }

    private func icon(_ name: String, active: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(active ? Color.onAccent : Color.secondary)
            .frame(width: 26, height: 26)
    }
}

/// Pins the lock switch to the right end of the title bar with an NSTitlebarAccessoryViewController.
/// Toolbar items can be pushed into the overflow (») menu while the sidebar animates; this can't.
struct LockSwitchAccessory: NSViewRepresentable {
    let model: AppModel
    private static let id = NSUserInterfaceItemIdentifier("slinky.lockSwitch")

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.install(in: view.window, model: model) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Self.install(in: nsView.window, model: model)
    }

    private static func install(in window: NSWindow?, model: AppModel) {
        guard let window, !window.titlebarAccessoryViewControllers.contains(where: { $0.identifier == id }) else { return }
        let size = NSSize(width: 66, height: 34)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 110, height: 52))   // room for the glass's shadow
        let content: NSView
        if #available(macOS 26, *) {
            // AppKit's Liquid Glass, so the switch is the same material as the toolbar's buttons.
            let host = NSHostingView(rootView: LockSwitch(inGlass: true).symbolVariant(.fill).environment(model))
            let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
            glass.cornerRadius = size.height / 2
            glass.contentView = host
            content = glass
        } else {
            content = NSHostingView(rootView: LockSwitch().symbolVariant(.fill).environment(model))
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            content.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            content.widthAnchor.constraint(equalToConstant: size.width),
            content.heightAnchor.constraint(equalToConstant: size.height),
        ])
        let accessory = NSTitlebarAccessoryViewController()
        accessory.identifier = id
        accessory.view = container
        accessory.layoutAttribute = .trailing
        // macOS 26 draws a scroll-edge backdrop behind title bar accessories, hard-edged by default: a pale box
        // around the switch. The soft style fades instead, so over the window's plain background it doesn't show.
        if #available(macOS 26.1, *) { accessory.preferredScrollEdgeEffectStyle = .soft }
        window.addTitlebarAccessoryViewController(accessory)
        // The glass's shadow reaches past the accessory's bounds; let it, up to the title bar itself, rather than
        // being cut off in a square around the switch.
        let frameView = window.contentView?.superview
        DispatchQueue.main.async {
            var view: NSView? = container
            while let v = view, v !== frameView, !String(describing: type(of: v)).contains("NSTitlebarView") {
                v.clipsToBounds = false
                view = v.superview
            }
        }
    }
}

/// The lock and unlock moment, drawn as the lock screen itself (LockStage) with the app icon's keyhole cut out.
/// Unlocking: the asterisk turns like a dial, the ring of characters scrambles, then the keyhole opens out
/// until the whole window is the app. Locking runs it backwards: the window closes in to the keyhole, and only
/// then does the vault lock. Nothing secret is drawn outside the keyhole.
struct LockCurtain: View {
    @Environment(AppModel.self) private var model
    @State private var hole: CGFloat = 1      // closed = a point in the keyhole, 0 = the icon's keyhole, 1 = the whole window
    private static let closed: CGFloat = -0.5
    @State private var spin: Double = 0
    @State private var scramble = false
    @State private var controls: Double = 1
    @State private var ring: CGFloat = 1
    @State private var shown = false

    private var visible: Bool { shown || model.curtain != .none }

    var body: some View {
        // The whole window, the strip behind the toolbar included, so nothing of the app shows around the edges.
        // `top` is that strip's height, so the mark still lines up with the lock screen's.
        GeometryReader { geo in
            let top = geo.safeAreaInsets.top
            LockStage(spin: spin, scramble: scramble ? 0.035 : nil, ringScale: ring, top: top) {
                LockControls(note: LockReason.manual.note, unlockLabel: model.unlockLabel)
                    .opacity(controls)
            }
            .mask {
                ZStack {
                    Rectangle()
                    KeyholeHole(progress: hole, top: top).blendMode(.destinationOut)
                }
                .compositingGroup()
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .onChange(of: model.curtain) { _, curtain in
            switch curtain {
            case .closing: Task { await close() }
            case .opening: Task { await open() }
            case .none: break
            }
        }
        .onChange(of: model.phase) { _, phase in
            // The vault just locked under the curtain, and the lock screen beneath looks the same: step aside.
            if phase == .locked, shown { reset() }
        }
        .onAppear {
            // Unlocked while the window was closed: nothing to play.
            if model.curtain == .opening { model.curtain = .none }
        }
        .accessibilityHidden(true)
    }

    private func open() async {
        quietly { hole = Self.closed; spin = 0; ring = 1; controls = 1; scramble = true; shown = true }
        // The dial turns and the words step back, then the keyhole opens out.
        withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) { spin = 60 }
        withAnimation(.easeOut(duration: 0.14)) { controls = 0 }
        try? await Task.sleep(for: .milliseconds(170))
        withAnimation(.easeIn(duration: 0.46)) { hole = 1; ring = 1.35 }
        try? await Task.sleep(for: .milliseconds(480))
        model.curtain = .none
        reset()
    }

    private func close() async {
        quietly { hole = 1; spin = 60; ring = 1.35; controls = 0; scramble = true; shown = true }
        // The window closes in to the keyhole, the dial turns back and the characters settle.
        withAnimation(.easeOut(duration: 0.44)) { hole = Self.closed; ring = 1 }
        try? await Task.sleep(for: .milliseconds(300))
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { spin = 0 }
        withAnimation(.easeIn(duration: 0.2)) { controls = 1 }
        try? await Task.sleep(for: .milliseconds(200))
        scramble = false
    }

    private func reset() {
        quietly { shown = false; hole = 1; spin = 0; ring = 1; controls = 1; scramble = false }
    }

    private func quietly(_ change: () -> Void) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t, change)
    }
}
