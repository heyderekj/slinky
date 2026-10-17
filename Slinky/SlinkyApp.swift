import AppKit
import SwiftUI

@main
struct SlinkyApp: App {
    @State private var model = AppModel.shared
    @State private var prefs = Preferences.shared

    var body: some Scene {
        Window("Slinky", id: "main") {
            RootView()
                .symbolVariant(.fill)   // filled SF Symbols everywhere (Derek, 2026-10-17)
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
                Divider()
                Button("Import from 1Password or CSV…") { model.beginImport() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
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
            SidebarCommands()
            CommandGroup(replacing: .help) {
                WindowCommand(title: "Slinky Help", id: "help")
            }
            CommandGroup(after: .appInfo) {
                Button("Lock Slinky") { model.lockAnimated() }
                    .keyboardShortcut("l", modifiers: [.command, .control])
                    .disabled(!model.isUnlocked)
            }
        }
        Window("Slinky Settings", id: "settings") {
            SettingsView()
                .symbolVariant(.fill)
                .environment(model)
                .environment(prefs)
                .background(TransparentTitlebar(autosaveName: "SlinkySettingsWindow"))
                .containerBackground(for: .window) { WindowGlass() }
        }
        // Same chrome as Dinky's Settings: a Window scene with a unified title bar showing the pane's name.
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 760, height: 560)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)

        Window("Slinky Help", id: "help") {
            HelpView()
                .symbolVariant(.fill)
                .background(TransparentTitlebar(autosaveName: "SlinkyHelpWindow"))
                .containerBackground(for: .window) { WindowGlass() }
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        MenuBarExtra(isInserted: $prefs.showInMenuBar) {
            MenuBarStack().symbolVariant(.fill).environment(model)
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

struct WindowCommand: View {
    let title: String
    let id: String
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button(title) {
            openWindow(id: id)
            NSApp.activate()
        }
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
        // The lock switch lives in the title bar, not the toolbar, so it never slides into the
        // toolbar's overflow menu while the sidebar opens or closes.
        .background(LockSwitchAccessory(model: model))
    }
}
