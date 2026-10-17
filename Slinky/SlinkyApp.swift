import AppKit
import SwiftUI

@main
struct SlinkyApp: App {
    @State private var model = AppModel.shared
    @State private var prefs = Preferences.shared

    var body: some Scene {
        Window("Slinky", id: "main") {
            RootView()
                .frame(minWidth: 880, minHeight: 560)
                .task {
                    model.start()
                    QuickAccess.shared.configure(model)
                }
                .background(WindowOpenerBridge())
                .background(TransparentTitlebar())
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .containerBackground(for: .window) { WindowGlass() }
                .environment(model)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 880, height: 560)   // opens at its smallest size, which is also its minimum
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Item…") {
                    model.tuckPrefill = ""
                    model.tuckProject = nil
                    model.showTuck = true
                }
                    .keyboardShortcut("n")
                    .disabled(!model.isUnlocked)
                Button("New Project…") { model.showNewProject = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(!model.isUnlocked)
            }
            CommandGroup(after: .newItem) {
                Button("Quick Access") { QuickAccess.shared.show() }
                    .keyboardShortcut("k", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .appInfo) {
                Button("About Slinky") { AboutPanel.show() }
            }
            CommandGroup(replacing: .appSettings) {
                SettingsCommand()
            }
            CommandGroup(after: .appInfo) {
                Button("Lock Slinky") { model.lockAnimated() }
                    .keyboardShortcut("l", modifiers: [.command, .control])
                    .disabled(!model.isUnlocked)
            }
        }
        Window("Slinky Settings", id: "settings") {
            SettingsView()
                .environment(model)
                .environment(prefs)
                .background(TransparentTitlebar(autosaveName: "SlinkySettingsWindow"))
                .containerBackground(for: .window) { WindowGlass() }
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        .restorationBehavior(.disabled)

        MenuBarExtra(isInserted: $prefs.showInMenuBar) {
            MenuBarStack().environment(model)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Content runs under a see-through title bar, Tahoe style (same idea as Binky's TransparentWindow).
struct TransparentTitlebar: NSViewRepresentable {
    var autosaveName = "SlinkyMainWindow"

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.apply(view.window, autosaveName) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) { Self.apply(nsView.window, autosaveName) }

    private static func apply(_ window: NSWindow?, _ autosaveName: String) {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        if window.frameAutosaveName != autosaveName { window.setFrameAutosaveName(autosaveName) }
    }
}

/// Settings… (⌘,) opens Slinky's own Settings window (a Window scene, like Binky's).
struct SettingsCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate()
        }
        .keyboardShortcut(",")
    }
}

/// Lets non-SwiftUI code (Quick Access) bring the main window back.
struct WindowOpenerBridge: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Color.clear.onAppear {
            model.openMainWindow = {
                openWindow(id: "main")
                NSApp.activate()
            }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .loading: ProgressView()
            case .locked: LockView()
            case .unlocked: MainView()
            }
        }
        .overlay { LockCurtain() }
        // While unlocked, toasts live over the detail column (MainView) so they center on the content.
        .overlay(alignment: .bottom) { if model.phase != .unlocked { ToastView() } }
        .toolbar {
            if model.phase != .loading {
                ToolbarItem(placement: .primaryAction) { LockSwitch() }
            }
        }
    }
}
