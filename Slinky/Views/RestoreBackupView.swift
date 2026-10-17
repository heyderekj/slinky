import AppKit
import SwiftUI

/// Restore from Backup…: pick the file, type the Recovery Key it was made with, restore.
struct RestoreBackupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var file: URL?
    @State private var recovery = ""
    @State private var message: String?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 26)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Restore from Backup").font(.headline)
                    Text("A backup opens with the Recovery Key you had when you made it.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Form {
                LabeledContent("Backup") {
                    HStack {
                        Text(file?.lastPathComponent ?? "No file chosen").foregroundStyle(file == nil ? .secondary : .primary)
                            .lineLimit(1).truncationMode(.middle)
                        Button("Choose…", action: choose)
                    }
                }
                TextField("Recovery Key", text: $recovery, prompt: Text("XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX"))
                    .font(.system(.body, design: .monospaced))
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 120)
            if model.hasVault {
                Label("This replaces the vault on this Mac. Slinky keeps one copy of it next to the vault file, but to be safe, export it first.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                if model.canExportBackup {
                    Button("Export Current Vault First…") { Task { await model.exportBackup() } }
                        .buttonStyle(.link)
                }
            }
            if let message, !message.isEmpty {
                Text(message).font(.callout).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(working ? "Restoring…" : "Restore") {
                    guard let file else { return }
                    working = true
                    Task {
                        message = await model.restoreBackup(from: file, recoveryText: recovery)
                        working = false
                        if message == nil { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .glassProminentButton()
                .disabled(file == nil || recovery.trimmingCharacters(in: .whitespaces).isEmpty || working)
            }
        }
        .padding(22)
        .frame(width: 480)
        .onDisappear { recovery = "" }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Slinky Backup"
        panel.allowedContentTypes = [AppModel.backupType, .data]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { file = panel.url }
    }
}
