import AppKit
import SwiftUI

/// Shown once, as a sheet, right after the first save creates the vault. Not a welcome screen.
struct RecoveryKeySheet: View {
    @Environment(AppModel.self) private var model
    let key: String
    /// True when this replaces an older key from Settings.
    var isReplacement = false
    /// Where Done goes. By default, it closes the first-save sheet.
    var onDone: (() -> Void)?
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                TurningMark(size: 44, onAppear: true)   // a vault was just made: the mark turns once
                VStack(alignment: .leading, spacing: 2) {
                    Text(isReplacement ? "Save your new Recovery Key" : "Save your Recovery Key").font(.title3.weight(.bold))
                    Text(isReplacement ? "Your old Recovery Key no longer works." : "Your vault is ready. Keep this key somewhere safe.")
                        .foregroundStyle(.secondary)
                }
            }
            Text(key)
                .font(.system(size: 21, weight: .semibold, design: .monospaced))
                .tracking(0.6)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.paper, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
            Text("You need this key to open your vault on another Mac, or if Touch ID stops working. Slinky doesn't keep a copy, so print it or store it in Apple Passwords.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Print…") { RecoveryPrinter.print(key) }
                Button("Copy") { model.copy(key, label: "your Recovery Key", remember: false) }
                Spacer()
            }
            .glassButton()
            Divider()
            HStack {
                Toggle("I've saved my Recovery Key", isOn: $saved)
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Done") {
                    if let onDone { onDone() } else { model.recoveryKeyToShow = nil }
                }
                    .glassProminentButton()
                    .keyboardShortcut(.defaultAction)
                    .disabled(!saved)
            }
        }
        .padding(24)
        .frame(width: 520)
        .interactiveDismissDisabled()
    }
}

enum RecoveryPrinter {
    /// With no title, prints Slinky's own Recovery Key. With a title, prints a saved account recovery key.
    static func print(_ key: String, title: String? = nil) {
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 468, height: 300))
        let date = Date.now.formatted(date: .long, time: .omitted)
        if let title {
            text.string = """
            \(title)

            \(key)

            Printed from Slinky on \(date). Keep this somewhere safe and offline.
            """
        } else {
            text.string = """
            Slinky Recovery Key

            \(key)

            Opens your Slinky vault on any Mac. Keep this somewhere safe and offline.
            Printed \(date).
            """
        }
        text.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        NSPrintOperation(view: text).run()
    }
}

/// The locked window is the app's window with the vault closed: the same toolbar and surface as when it's open,
/// no sidebar, and the app icon as the lock in the middle (LockStage). Touch ID is usually already asking.
struct LockView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var autoUnlock = true
    @State private var showRecovery = false
    @State private var recoveryText = ""

    var body: some View {
        // The ring scrambles while Touch ID waits; with Reduce Motion it stays still (the button's pulse says it's waiting).
        LockStage(showFace: model.phase == .locked, scramble: model.busy && !reduceMotion ? 0.09 : nil) {
            LockControls(note: model.lockNote, busy: model.busy, error: model.errorMessage, unlockLabel: model.unlockLabel,
                         unlock: { model.unlock() }, useRecoveryKey: { showRecovery = true })
        }
        .navigationTitle("Slinky")
        .navigationSubtitle(model.phase == .locked ? "Locked" : "")
        .toolbar {
            // The same toolbar as the open window, resting: nothing to show or add while locked.
            ToolbarItem(placement: .navigation) {
                Button {} label: { Label("Sidebar", systemImage: "sidebar.left") }
                    .disabled(true)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {} label: { Label("Add Item", systemImage: "plus") }
                    .disabled(true)
                    .help("Unlock Slinky to add items")
            }
        }
        .sheet(isPresented: $showRecovery) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Unlock with your Recovery Key").font(.headline)
                Text("For a new Mac, a restored backup, or if Touch ID stopped working. Slinky sets up Touch ID again afterwards.")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX", text: $recoveryText)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { showRecovery = false }
                    Button("Unlock") {
                        if model.unlock(recoveryText: recoveryText) { showRecovery = false }
                    }
                    .glassProminentButton()
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(22)
            .frame(width: 460)
        }
        .task {
            // Ask straight away on open; the button is there if they cancel.
            if autoUnlock, model.phase == .locked, model.lockNote == nil, model.errorMessage == nil { model.unlock() }
        }
    }
}
