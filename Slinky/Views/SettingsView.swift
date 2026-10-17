import AppKit
import SlinkyCoreVault
import SwiftUI

/// Settings, Binky-style: a Window scene with a sidebar of panes and grouped forms.
/// Small on purpose. No secret, name or value is ever stored here.
struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general, security, recovery, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .security: "Security"
            case .recovery: "Recovery Key"
            case .about: "About"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .security: "lock"
            case .recovery: "lifepreserver"
            case .about: "info.circle"
            }
        }
    }

    @State private var pane: Pane? = .general

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { pane in
                Label(pane.title, systemImage: pane.symbol).tag(pane)
            }
            .navigationSplitViewColumnWidth(190)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch pane ?? .general {
                case .general: GeneralPane()
                case .security: SecurityPane()
                case .recovery: RecoveryKeyPane()
                case .about: AboutPane()
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .navigationTitle((pane ?? .general).title)
        }
        .frame(width: 700, height: 500)
    }
}

private struct GeneralPane: View {
    @Environment(Preferences.self) private var prefs
    @State private var loginMessage: String?

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            Section {
                Toggle("Open Slinky when you log in", isOn: Binding(
                    get: { prefs.openAtLogin },
                    set: { loginMessage = prefs.setOpenAtLogin($0) }))
                if let loginMessage {
                    Text(loginMessage).font(.caption).foregroundStyle(.orange)
                }
                Toggle("Show Slinky in the menu bar", isOn: $prefs.showInMenuBar)
            }
            Section {
                Toggle("Play sounds", isOn: $prefs.playSounds)
            } footer: {
                Text("A soft sound when you save something, a bigger one when you import a .env file, and a click when you lock.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Quick Access") { Keycap("⌥⌘K") }
                LabeledContent("Add Item") { Keycap("⌘N") }
                LabeledContent("New Project") { Keycap("⇧⌘N") }
                LabeledContent("Lock Slinky") { Keycap("⌃⌘L") }
            } header: {
                Text("Keyboard shortcuts")
            }
        }
        .onAppear { prefs.refreshLoginItem() }
    }
}

private struct SecurityPane: View {
    @Environment(Preferences.self) private var prefs
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            Section {
                Picker("Lock after", selection: $prefs.autoLockMinutes) {
                    ForEach(Preferences.autoLockChoices, id: \.self) { m in
                        Text(m == 60 ? "1 hour away" : "\(m) minutes away").tag(m)
                    }
                }
                Toggle("Lock when the screen locks", isOn: $prefs.lockOnScreenLock)
                Toggle("Lock when your Mac goes to sleep", isOn: $prefs.lockOnSleep)
            } header: {
                Text("Locking")
            } footer: {
                Text("\"Away\" means you haven't touched the keyboard, mouse or trackpad. Slinky also locks after 12 hours, whatever you choose here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker("Clear the clipboard after", selection: $prefs.clipboardSeconds) {
                    ForEach(Preferences.clipboardChoices, id: \.self) { s in
                        Text(s == 120 ? "2 minutes" : "\(s) seconds").tag(s)
                    }
                }
            } header: {
                Text("Clipboard")
            } footer: {
                Text("Only if you haven't copied anything else since. Slinky marks what it copies as private, so clipboard history apps skip it and it doesn't go to your other devices.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.isUnlocked && model.hasVault {
                Section {
                    HStack {
                        Spacer()
                        Button("Lock Now") { model.lockAnimated() }
                            .buttonStyle(.glass)
                    }
                }
            }
        }
    }
}

private struct RecoveryKeyPane: View {
    @Environment(AppModel.self) private var model
    @State private var confirm = false
    @State private var newKey: String?
    @State private var working = false

    var body: some View {
        Form {
            Section {
                Text("Your Recovery Key opens your vault on another Mac, or if Touch ID stops working. Slinky showed it once, when you saved your first item, and doesn't keep a copy.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                if !model.hasVault {
                    Text("Your Recovery Key is made when you save your first item.")
                        .foregroundStyle(.secondary)
                } else if !model.isUnlocked {
                    Text("Unlock Slinky to make a new Recovery Key.")
                        .foregroundStyle(.secondary)
                } else {
                    LabeledContent {
                        Button("Make a New Recovery Key…") { confirm = true }
                            .disabled(working)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Lost it, or think someone saw it?")
                            Text("A new key replaces the old one. The old one stops working.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                LabeledContent("Vault file") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([VaultStore.defaultURL])
                    }
                    .disabled(!model.hasVault)
                }
            } footer: {
                Text("Time Machine backs up your vault file like any other file. It stays encrypted, and only your Mac's Touch ID or your Recovery Key can open it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("Make a new Recovery Key?", isPresented: $confirm) {
            Button("Make New Key") {
                working = true
                Task {
                    newKey = await model.makeNewRecoveryKey()
                    working = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current Recovery Key will stop working. You'll need to print or save the new one.")
        }
        .sheet(isPresented: Binding(get: { newKey != nil }, set: { if !$0 { newKey = nil } })) {
            if let newKey {
                RecoveryKeySheet(key: newKey, isReplacement: true) { self.newKey = nil }
            }
        }
    }
}

private struct AboutPane: View {
    @Environment(AppModel.self) private var model
    @Environment(Preferences.self) private var prefs

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "Version \(info?["CFBundleShortVersionString"] as? String ?? "1.0") (\(info?["CFBundleVersion"] as? String ?? "1"))"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    KeyholeMark(size: 72)
                    Text("Slinky").font(.title.weight(.bold))
                    Text("Slinky keeps secrets out of files.").foregroundStyle(.secondary)
                    Text(version).font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section {
                if model.isUnlocked {
                    LabeledContent("Kept out of your files", value: "\(model.document.secretCount) \(model.document.secretCount == 1 ? "secret" : "secrets")")
                }
                LabeledContent("Copied for you", value: "\(prefs.copyCount) \(prefs.copyCount == 1 ? "time" : "times")")
                LabeledContent("Seen by", value: "You")
            }
            Section {
                Link("slinkyfiles.com", destination: URL(string: "https://slinkyfiles.com")!)
                Link("Source code on GitHub", destination: URL(string: "https://github.com/heyderekj/slinky")!)
                Link("help@slinkyfiles.com", destination: URL(string: "mailto:help@slinkyfiles.com")!)
            } footer: {
                Text("Made by Testament Made, LLC. Free and open source under the MIT License.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
