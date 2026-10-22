import AppKit
import SlinkyCoreVault
import SwiftUI

/// Settings, Binky-style: a Window scene with a sidebar of panes and grouped forms.
/// Small on purpose. No secret, name or value is ever stored here.
struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general, security, recovery, sync, agents, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .security: "Security"
            case .recovery: "Recovery Key"
            case .sync: "Sync"
            case .agents: "Command Line & Agents"
            case .about: "About"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .security: "lock"
            case .recovery: "lifepreserver"
            case .sync: "arrow.triangle.2.circlepath"
            case .agents: "terminal"
            case .about: "info.circle"
            }
        }
    }

    // Back and forward, like Dinky's Settings.
    @State private var history: [Pane] = [.general]
    @State private var index = 0

    private var pane: Pane { history[index] }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { pane }, set: { select($0) })) {
                Section("Settings") {
                    ForEach([Pane.general, .security, .recovery, .sync, .agents]) { row($0) }
                }
                Section("Slinky") {
                    row(.about)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("")
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            NavigationStack {
                Group {
                    switch pane {
                    case .general: GeneralPane()
                    case .security: SecurityPane()
                    case .recovery: RecoveryKeyPane()
                    case .agents: AgentsPane()
                    case .sync: SyncPane()
                    case .about: AboutPane()
                    }
                }
                .formStyle(.grouped)
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(pane.title)
                .toolbar {
                    // One shared capsule, like Finder's and System Settings' back and forward. No button style
                    // of our own: the toolbar draws them (glass on Tahoe, standard on Sequoia).
                    ToolbarItemGroup(placement: .navigation) {
                        Button { index -= 1 } label: { Label("Back", systemImage: "chevron.backward") }
                            .help("Back")
                            .disabled(index == 0)
                        Button { index += 1 } label: { Label("Forward", systemImage: "chevron.forward") }
                            .help("Forward")
                            .disabled(index >= history.count - 1)
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .frame(minWidth: 760, minHeight: 560)
    }

    private func row(_ pane: Pane) -> some View {
        Label(pane.title, systemImage: pane.symbol).tag(pane)
    }

    private func select(_ new: Pane) {
        guard new != pane else { return }
        history = Array(history.prefix(index + 1)) + [new]
        index = history.count - 1
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
                    Text(loginMessage).font(.caption).foregroundStyle(Color.attention)
                }
                Toggle("Show Slinky in the menu bar", isOn: $prefs.showInMenuBar)
            }
            Section {
                Toggle("Check for updates automatically", isOn: $prefs.checkForUpdates)
                LabeledContent("Slinky \(Updater.shared.currentVersion)") {
                    Button(Updater.shared.isChecking ? "Checking…" : "Check Now") { Updater.shared.checkManually() }
                        .disabled(Updater.shared.isChecking)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Once a day, Slinky asks GitHub whether there's a newer version. Nothing about you or your vault is sent.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Load icons from websites", isOn: $prefs.loadWebsiteIcons)
            } header: {
                Text("Icons")
            } footer: {
                Text("Slinky shows the app or logo for services it knows, without going online. With this on, for anything else it asks the item's website for its icon. The request goes straight to that website, and the icon is kept in your vault.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Offer to save keys you copy in other apps", isOn: $prefs.offerToSaveCopies)
                Toggle("Remind me about expiring keys, low codes and leaks", isOn: Binding(get: { prefs.reminders }, set: { on in
                    prefs.reminders = on
                    if on { Task { _ = await Reminders.requestPermission() } }
                }))
            } header: {
                Text("Helping out")
            } footer: {
                Text("Saving checks only what a copied value looks like, and keeps nothing unless you choose Save. Copies from password managers are skipped. Reminders are Mac notifications with names only, never values.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Play sounds", isOn: $prefs.playSounds)
                    .onChange(of: prefs.playSounds) { _, on in if on { Sounds.play(.saved) } }
            } footer: {
                Text("The soft ripple of a Slinky's coils and a latch clicking shut when you save or import, and the lock closing or opening.")
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
                        Text(Preferences.clipboardDuration(s)).tag(s)
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
                            .glassButton()
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
    @State private var restoring = false

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
                LabeledContent {
                    Button("Export Backup…") { Task { await model.exportBackup() } }
                        .disabled(!model.canExportBackup)
                } label: {
                    Text("Export a backup")
                    Text(Preferences.shared.lastBackup.map { "Last one \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "None yet")
                }
                LabeledContent("Restore") {
                    Button("Restore from Backup…") { restoring = true }
                        .disabled(!model.canRestoreBackup)
                }
            } header: {
                Text("Backups")
            } footer: {
                Text("A backup is your whole vault in one encrypted file, to keep somewhere else. It opens only with the Recovery Key you have when you make it, so after making a new Recovery Key, export a new backup.")
                    .font(.caption).foregroundStyle(.secondary)
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
        .sheet(isPresented: $restoring) { RestoreBackupView() }
        .sheet(isPresented: Binding(get: { newKey != nil }, set: { if !$0 { newKey = nil } })) {
            if let newKey {
                RecoveryKeySheet(key: newKey, isReplacement: true) { self.newKey = nil }
            }
        }
    }
}

/// Settings › Sync: the vault, the same on each of your Macs, through a folder you choose. Honest about what
/// goes where: an encrypted copy in that folder, moved by your sync service; nothing sent by Slinky.
private struct SyncPane: View {
    @Environment(AppModel.self) private var model
    @State private var recoveryText = ""
    @State private var problem: String?
    @State private var working = false
    private var sync: VaultSync { .shared }

    var body: some View {
        Form {
            Section {
                if let folder = sync.folder {
                    LabeledContent("Folder") {
                        HStack(spacing: 8) {
                            Text((folder.path as NSString).abbreviatingWithTildeInPath)
                                .font(.callout.monospaced()).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.head)
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([sync.copyURL ?? folder])
                            }
                        }
                    }
                    LabeledContent("Status") {
                        if let p = sync.problem {
                            Text(p).foregroundStyle(Color.attention).fixedSize(horizontal: false, vertical: true)
                        } else if let last = sync.lastSynced {
                            Text("Synced \(last.formatted(.relative(presentation: .named)))" + (sync.serviceName.map { " · \($0)" } ?? ""))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(model.isUnlocked ? "Waiting to sync" : "Syncs when Slinky is unlocked").foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Button("Sync Now") { sync.pull(thenPush: true) }
                            .disabled(!model.isUnlocked)
                        Spacer()
                        Button("Stop Syncing", role: .destructive) { sync.stop() }
                    }
                } else {
                    LabeledContent("Sync folder") {
                        Button(model.hasVault ? "Choose Folder…" : "Use a Vault from a Sync Folder…", action: choose)
                            .disabled(model.hasVault && !model.isUnlocked)
                    }
                }
            } footer: {
                Text("Keeps your vault the same on each of your Macs, through a folder you choose, like one in iCloud Drive or Dropbox. Slinky puts an encrypted copy of the vault there and your sync service moves it. It opens only with your Recovery Key or on a Mac you've set up, so the sync service can't read it. Slinky itself sends nothing anywhere. The copy is also a backup.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let foreign = sync.foreignCopy {
                Section {
                    Text("This folder already has a Slinky vault, from another Mac. Enter its Recovery Key to use it here. Slinky adds this Mac's items to it.")
                        .fixedSize(horizontal: false, vertical: true)
                    SecureField("Recovery Key", text: $recoveryText, prompt: Text("XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX"))
                        .labelsHidden()
                        .font(.body.monospaced())
                    if let problem, !problem.isEmpty {
                        Text(problem).foregroundStyle(Color.danger).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Spacer()
                        Button("Cancel") { sync.cancelForeign(); recoveryText = "" }
                        Button(working ? "Opening…" : "Use This Vault") { adopt(foreign) }
                            .glassProminentButton()
                            .disabled(recoveryText.trimmingCharacters(in: .whitespaces).isEmpty || working)
                    }
                } header: {
                    Text("Use the vault in this folder")
                } footer: {
                    Text("After this, the synced vault's Recovery Key opens everything on this Mac, and this Mac's old Recovery Key no longer does. The vault this Mac had is kept, untouched, as a file you can restore.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onDisappear { recoveryText = "" }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Sync Here"
        panel.message = "Choose a folder your sync service keeps on all your Macs, like one in iCloud Drive. Slinky puts an encrypted copy of your vault in it."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if model.hasVault {
            sync.choose(url)
        } else if FileManager.default.fileExists(atPath: url.appendingPathComponent("Slinky/vault.slinky").path) {
            sync.offerForeign(url.appendingPathComponent("Slinky/vault.slinky"))
        } else {
            problem = "There's no Slinky vault in that folder yet. Turn on sync on the Mac that has your vault first."
        }
    }

    private func adopt(_ url: URL) {
        working = true
        problem = nil
        Task {
            problem = await model.adoptSyncedVault(at: url, recoveryText: recoveryText)
            working = false
            if problem == nil { recoveryText = "" }
        }
    }
}

private struct AboutPane: View {
    @Environment(AppModel.self) private var model
    @Environment(Preferences.self) private var prefs

    private var version: String {
        let info = Bundle.main.infoDictionary
        // The version people see on the site and in updates; the build number means nothing to them.
        return "Version \(info?["CFBundleShortVersionString"] as? String ?? "1.0")"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    TurningMark(size: 72, onClick: true)
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
                Link("derek@testamentmade.com", destination: URL(string: "mailto:derek@testamentmade.com")!)
            } footer: {
                Text("Made by Testament Made, LLC. Free and open source under the MIT License.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
