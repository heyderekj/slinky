import AppKit
import SwiftUI

@main
struct SlinkyApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Slinky", id: "main") {
            RootView()
                .frame(minWidth: 880, minHeight: 560)
                .task {
                    model.start()
                    QuickAccess.shared.configure(model)
                }
                .background(WindowOpenerBridge())
                .environment(model)
        }
        .defaultSize(width: 1120, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Tuck It Away…") { model.showTuck = true }
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
            CommandGroup(after: .appInfo) {
                Button("Lock Slinky") { model.lock(reason: .manual) }
                    .keyboardShortcut("l", modifiers: [.command, .control])
                    .disabled(!model.isUnlocked)
            }
        }
        MenuBarExtra("Slinky", systemImage: "asterisk") {
            MenuBarStack().environment(model)
        }
        .menuBarExtraStyle(.window)
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
            case .welcome: WelcomeView()
            case let .recoveryKey(key): RecoveryKeyView(key: key)
            case .locked: LockView()
            case .unlocked: MainView()
            }
        }
        .overlay(alignment: .bottom) { ToastView() }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: model.phase)
    }
}
