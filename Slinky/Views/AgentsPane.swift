import AppKit
import SwiftUI

/// Settings › Command Line & Agents: the `slinky` command, the shell hook, and AI tools.
/// Every change to a config file says what it does first, keeps a backup, and can be undone.
struct AgentsPane: View {
    @State private var command = Integrations.commandState
    @State private var onPath = true
    @State private var hasPathLine = Integrations.zshrcHas(Integrations.pathLine)
    @State private var hasHook = Integrations.zshrcHas(Integrations.hookLine)
    @State private var connected: Set<Integrations.Tool> = []
    @State private var confirming: Integrations.Tool?
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Button(command == .missing ? "Install" : command == .stale ? "Update" : "Reinstall") { act { try Integrations.installCommand() } }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("The slinky command")
                        Text(command == .installed ? "Installed in ~/.local/bin" : command == .stale ? "Points at another copy of Slinky" : "Not installed")
                            .font(.caption).foregroundStyle(command == .installed ? Color.secondary : Color.orange)
                    }
                }
                if command == .installed, !onPath, !hasPathLine {
                    LabeledContent {
                        Button("Add to ~/.zshrc") { act { try Integrations.addToZshrc(Integrations.pathLine, comment: "the slinky command") } }
                    } label: {
                        Text("Terminal can't find it yet").font(.callout)
                    }
                }
                CommandExample("slinky run -- npm run dev", note: "Runs with your project's variables, after Touch ID.")
                CommandExample("slinky check", note: "Lists what this project still needs.")
            } header: {
                Text("Command line")
            } footer: {
                Text("The command asks Slinky, and Slinky asks you. It never reads the vault itself, and nothing it prints is a value unless you approved a command that needs it.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Load a project's variables when you cd into its folder", isOn: Binding(get: { hasHook }, set: { on in
                    act { on ? try Integrations.addToZshrc(Integrations.hookLine, comment: "load Slinky project variables on cd")
                             : try Integrations.removeFromZshrc(Integrations.hookLine) }
                }))
                .disabled(command != .installed)
            } header: {
                Text("Shell (zsh)")
            } footer: {
                Text("One Touch ID per project per hour, and they're unloaded when you leave the folder. While loaded, other programs you start from that shell can read them, like any environment variable.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach(Integrations.Tool.allCases.filter { $0.isPresent || connected.contains($0) }) { tool in
                    LabeledContent {
                        if connected.contains(tool) {
                            Button("Disconnect") { act { try Integrations.disconnect(tool) } }
                        } else {
                            Button("Connect…") { confirming = tool }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.name)
                            Text(connected.contains(tool) ? "Connected" : "Not connected")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if !Integrations.Tool.allCases.contains(where: \.isPresent) {
                    Text("No AI tools found. Claude Code, Cursor, Codex and Claude can connect once they're installed.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("AI tools")
            } footer: {
                Text("Agents see names, never values. To use a secret they run a command through slinky run, and you approve it with Touch ID. Live keys stay out of agent runs.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                CommandExample("slinky guard install", note: "In a git repository: stops commits that contain a secret saved in Slinky.")
            } header: {
                Text("Git")
            }

            if let message {
                Text(message).font(.callout).foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
        .task { await refresh() }
        .confirmationDialog("Connect \(confirming?.name ?? "")?", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })) {
            Button("Connect") {
                if let tool = confirming { act { try Integrations.connect(tool) } }
                confirming = nil
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        } message: {
            Text((confirming?.preview ?? "") + " A backup is kept next to each file, and Disconnect undoes it.")
        }
    }

    private func act(_ change: () throws -> Void) {
        do { try change(); message = nil } catch { message = "Couldn't change that: \(error.localizedDescription)" }
        Task { await refresh() }
    }

    private func refresh() async {
        command = Integrations.commandState
        hasPathLine = Integrations.zshrcHas(Integrations.pathLine)
        hasHook = Integrations.zshrcHas(Integrations.hookLine)
        connected = Set(Integrations.Tool.allCases.filter { Integrations.isConnected($0) })
        onPath = await Integrations.commandOnPath() || hasPathLine
    }
}

/// A command to type, with a copy button. (Not a secret, so a plain copy.)
private struct CommandExample: View {
    let command: String
    let note: String
    @State private var copied = false

    init(_ command: String, note: String) { self.command = command; self.note = note }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(command).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
                Task { try? await Task.sleep(for: .seconds(1.4)); copied = false }
            }
            .controlSize(.small)
        }
    }
}
