import SwiftUI

/// The toolbar lock: a small switch with both states visible. The knob sits on the current one.
struct LockSwitch: View {
    @Environment(AppModel.self) private var model

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
        .glass(in: .capsule, interactive: true)
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
        let host = NSHostingView(rootView:
            LockSwitch()
                .symbolVariant(.fill)
                .environment(model)
                .frame(maxHeight: .infinity)
                .padding(.trailing, 14))
        host.frame = NSRect(x: 0, y: 0, width: 94, height: 52)
        let accessory = NSTitlebarAccessoryViewController()
        accessory.identifier = id
        accessory.view = host
        accessory.layoutAttribute = .trailing
        window.addTitlebarAccessoryViewController(accessory)
    }
}

/// The lock and unlock moment, across the whole window.
/// Locking: ice spreads out from the switch until it covers everything, and the lock in the middle closes.
/// Unlocking: the lock opens, then the ice opens from the middle like an iris to show the vault.
/// Nothing secret is ever drawn under the ice: the vault locks only once it's fully covered.
struct LockCurtain: View {
    @Environment(AppModel.self) private var model
    @State private var cover: CGFloat = 0     // closing: radius of the ice, from the switch
    @State private var hole: CGFloat = 0      // opening: radius of the gap, from the middle
    @State private var closedGlyph = false
    @State private var shown = false
    @State private var fade: Double = 1

    private var opening: Bool { model.curtain == .opening }
    private var visible: Bool { shown || model.curtain != .none }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let reach = hypot(size.width, size.height) * 1.05
            let origin = CGPoint(x: size.width - 47, y: 26)   // the lock switch, top right
            let middle = CGPoint(x: size.width / 2, y: size.height / 2)
            ZStack {
                IceBackdrop()
                Image(systemName: closedGlyph ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(.tint)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 120, height: 120)
                    .glass(in: .circle)
                    .scaleEffect(opening ? 1 + hole * 0.5 : 0.85 + cover * 0.15)
                    .opacity(opening ? 1 - hole * 1.6 : Double(cover))
                    .position(middle)
            }
            .mask {
                if opening {
                    ZStack {
                        Rectangle()
                        Circle()
                            .frame(width: reach * 2 * hole, height: reach * 2 * hole)
                            .position(middle)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                } else {
                    Circle()
                        .frame(width: reach * 2 * cover, height: reach * 2 * cover)
                        .position(origin)
                }
            }
            .overlay {
                // A bright rim on the leading edge of the ice while it spreads.
                if !opening, cover > 0, cover < 1 {
                    Circle()
                        .strokeBorder(.white.opacity(0.55), lineWidth: 1.5)
                        .frame(width: reach * 2 * cover, height: reach * 2 * cover)
                        .position(origin)
                        .blur(radius: 1)
                }
            }
        }
        .ignoresSafeArea()
        .opacity(visible ? fade : 0)
        .allowsHitTesting(visible)
        .onChange(of: model.curtain) { _, curtain in
            switch curtain {
            case .closing: Task { await close() }
            case .opening: Task { await open() }
            case .none: break
            }
        }
        .onChange(of: model.phase) { _, phase in
            // The vault just locked under the ice: let the lock screen show through.
            if phase == .locked, shown { Task { await settle() } }
        }
        .onAppear {
            // Unlocked while the window was closed: nothing to play.
            if model.curtain == .opening { model.curtain = .none }
        }
        .accessibilityHidden(true)
    }

    private func close() async {
        hole = 0
        cover = 0
        fade = 1
        closedGlyph = false
        shown = true
        withAnimation(.easeInOut(duration: 0.55)) { cover = 1 }
        try? await Task.sleep(for: .milliseconds(330))
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { closedGlyph = true }
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(380))
        withAnimation(.easeOut(duration: 0.35)) { fade = 0 }
        try? await Task.sleep(for: .milliseconds(380))
        reset()
    }

    private func open() async {
        cover = 1
        hole = 0
        fade = 1
        closedGlyph = true
        shown = true
        try? await Task.sleep(for: .milliseconds(120))
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { closedGlyph = false }
        try? await Task.sleep(for: .milliseconds(380))
        withAnimation(.easeInOut(duration: 0.6)) { hole = 1 }
        try? await Task.sleep(for: .milliseconds(620))
        model.curtain = .none
        reset()
    }

    private func reset() {
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            shown = false
            cover = 0
            hole = 0
            fade = 1
            closedGlyph = false
        }
    }
}
