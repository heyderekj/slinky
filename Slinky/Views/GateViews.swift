import AppKit
import SwiftUI

/// First run. The empty state is the onboarding.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            KeyholeMark(size: 112)
            Text("Slinky keeps secrets out of your files.")
                .font(.system(size: 26, weight: .bold))
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 10) {
                Label("API keys, project .env values, recovery codes, and anything a site says to keep safe.", systemImage: "tray.full")
                Label("Locked by your Mac's Secure Enclave. Touch ID to open.", systemImage: "touchid")
                Label("Nothing leaves this Mac. No account, no cloud.", systemImage: "laptopcomputer")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 440, alignment: .leading)
            Button("Create My Vault") { model.createVault() }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            if let error = model.errorMessage {
                Text(error).font(.callout).foregroundStyle(.red).frame(maxWidth: 440)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

/// Shown once, right after creating the vault.
struct RecoveryKeyView: View {
    @Environment(AppModel.self) private var model
    let key: String
    @State private var saved = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "key.horizontal")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
            Text("Your Recovery Key")
                .font(.system(size: 24, weight: .bold))
            Text("It opens your vault on a new Mac, or if this one forgets you. Slinky never stores it. Print it, or keep it in Apple Passwords. Never in Slinky.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 480)
            Text(key)
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .tracking(1)
                .textSelection(.enabled)
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .background(.background.secondary, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator, lineWidth: 0.5))
            HStack {
                Button("Print It…") { RecoveryPrinter.print(key) }
                Button("Copy") { model.copy(key, label: "your Recovery Key") }
            }
            .buttonStyle(.glass)
            Toggle("I've saved it somewhere safe, outside Slinky", isOn: $saved)
                .toggleStyle(.checkbox)
            Button("Continue") { model.finishOnboarding() }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!saved)
                .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

enum RecoveryPrinter {
    static func print(_ key: String) {
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 468, height: 300))
        text.string = """
        Slinky Recovery Key

        \(key)

        Opens your Slinky vault on any Mac. Keep this somewhere safe and offline.
        Printed \(Date.now.formatted(date: .long, time: .omitted)).
        """
        text.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        NSPrintOperation(view: text).run()
    }
}

struct LockView: View {
    @Environment(AppModel.self) private var model
    @State private var showRecovery = false
    @State private var recoveryText = ""

    var body: some View {
        VStack(spacing: 16) {
            KeyholeMark(size: 96)
            Text("Locked. Touch ID to peek.")
                .font(.system(size: 22, weight: .bold))
            if let note = model.lockNote {
                Text(note).foregroundStyle(.secondary)
            }
            Button {
                model.unlock()
            } label: {
                Label(model.unlockLabel, systemImage: "touchid")
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(model.busy)
            if let error = model.errorMessage {
                Text(error).font(.callout).foregroundStyle(.red).frame(maxWidth: 420).multilineTextAlignment(.center)
            }
            Button("Use Recovery Key…") { showRecovery = true }
                .buttonStyle(.link)
                .font(.callout)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .sheet(isPresented: $showRecovery) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Unlock with your Recovery Key").font(.headline)
                Text("For a new Mac, a restored backup, or if Touch ID stopped working. Slinky will set up Touch ID again afterwards.")
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
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(22)
            .frame(width: 460)
        }
        .task {
            // Ask straight away on open; the button is there if they cancel.
            if model.lockNote == nil, model.errorMessage == nil { model.unlock() }
        }
    }
}
