import AppKit
import SlinkyCoreShared
import SlinkyCoreVault
import SwiftUI

// Sharing with people: the Share panel (pick people, Touch ID, then send the file any way you like), the panel for
// a share someone sent you, the team sheet for a shared project, and the list of keys to replace after someone
// leaves. Values never show here: names, peeks and counts only.

// MARK: Picking people

/// Everyone in People except you, with a checkbox each. Unchecked codes are said plainly.
struct PeoplePicker: View {
    @Environment(AppModel.self) private var model
    @Binding var chosen: Set<UUID>
    var excluding: Set<UUID> = []

    private var people: [Person] { model.document.people.filter { !$0.isMe && !excluding.contains($0.id) } }

    @State private var pasted = ""

    var body: some View {
        if people.isEmpty {
            // No dead end: add someone right here, then they're ticked.
            VStack(alignment: .leading, spacing: 10) {
                Text("No one to share with yet. Paste the card someone sent you, or send them yours first.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                TextField("Their card", text: $pasted, prompt: Text("slinky-card:v1:…"))
                    .font(.callout.monospaced())
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.surface, in: .rect(cornerRadius: 10))
                if let card = PersonCard(text: pasted) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.name).fontWeight(.semibold)
                            CodeText(code: card.fingerprint, size: 15)
                        }
                        Spacer()
                        Button("Add \(card.name)") {
                            model.addCard(card)
                            pasted = ""
                            if let added = model.document.person(for: card) { chosen.insert(added.id) }
                        }
                        .glassButton()
                    }
                    Text("Compare this code with \(card.name) when you can, in People.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let url = model.myCardFile() {
                    ShareLink(item: url) { Label("Send Your Card…", systemImage: "square.and.arrow.up") }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.paper, in: .rect(cornerRadius: 18))
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                        if index > 0 { Divider().padding(.leading, 44) }
                        Toggle(isOn: Binding(get: { chosen.contains(person.id) },
                                             set: { if $0 { chosen.insert(person.id) } else { chosen.remove(person.id) } })) {
                            HStack(spacing: 8) {
                                Text(person.name).fontWeight(.medium)
                                if person.cards.count > 1 { Text("\(person.cards.count) Macs").foregroundStyle(.secondary) }
                                if !person.checked { Chip(text: "Code not compared", style: .warn) }
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            // As tall as the people in it, up to five rows.
            .frame(height: min(CGFloat(people.count) * 38 + 4, 194))
            .background(Color.paper, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1))
        }
    }
}

// MARK: Sending

struct ShareOverlay: View {
    @Environment(AppModel.self) private var model
    let draft: ShareDraft

    var body: some View {
        ZStack {
            PanelBackdrop(close: close)
            SharePanel(draft: draft, close: close)
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { model.sharing = nil }
    }
}

private struct SharePanel: View {
    @Environment(AppModel.self) private var model
    let draft: ShareDraft
    let close: () -> Void

    @State private var chosen: Set<UUID> = []
    @State private var remind = false
    @State private var remindOn = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    @State private var working = false
    @State private var made: URL?
    @State private var appeared = false

    private var names: [String] { draft.items.names }
    private var who: String { AppModel.list(model.document.people.filter { chosen.contains($0.id) }.map(\.name)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "person.2")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.14), in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Share").font(.headline)
                    Text(names.count == 1 ? names[0] : "\(names.count) items" + (draft.projectName.map { " from \($0)" } ?? ""))
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                PanelCloseButton(action: close)
            }
            .padding(.bottom, 14)

            if let made {
                ready(made)
            } else {
                Text("With").font(.callout.weight(.semibold)).padding(.bottom, 6)
                PeoplePicker(chosen: $chosen)

                // The title already names a single item.
                if names.count > 1 {
                    Text(names.joined(separator: ", "))
                        .font(.callout.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(3).truncationMode(.tail)
                        .padding(.top, 12)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Remind me to make new keys", isOn: $remind).toggleStyle(.checkbox)
                    if remind {
                        DatePicker("On", selection: $remindOn, in: Date.now..., displayedComponents: .date)
                            .datePickerStyle(.field).labelsHidden().padding(.leading, 20)
                    }
                    Text("Only the people you pick can open the file. They keep what you send, so when they no longer need it, make new keys.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 14)

                HStack(spacing: 10) {
                    if working { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Cancel", action: close).keyboardShortcut(.cancelAction).glassButton()
                    Button("Share…", action: share)
                        .keyboardShortcut(.defaultAction)
                        .glassProminentButton()
                        .disabled(chosen.isEmpty || working)
                }
                .dialogButtons()
                .padding(.top, 16)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 520)
        .glass(in: .rect(cornerRadius: 28))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 14)
        .panelEntrance(appeared)
        .onAppear { withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) { appeared = true } }
    }

    private func ready(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Ready. Only \(who) can open it, on a Mac whose card you added.", systemImage: "checkmark.seal")
                .fixedSize(horizontal: false, vertical: true)
            Text("Send it any way you like: AirDrop, Messages, Mail, a chat. The file is encrypted, so whoever carries it can't read it. When it's sent, delete it.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.glassButton()
                Spacer()
                Button("Done", action: close).keyboardShortcut(.cancelAction).glassButton()
                ShareLink(item: url) { Text("Send…") }
                    .keyboardShortcut(.defaultAction)
                    .glassProminentButton()
            }
            .dialogButtons()
        }
    }

    private func share() {
        working = true
        Task {
            made = await model.makeShare(draft, to: chosen, remindOn: remind ? remindOn : nil)
            working = false
        }
    }
}

// MARK: Receiving

struct ReceiveOverlay: View {
    @Environment(AppModel.self) private var model
    let share: ReceivedShare

    var body: some View {
        ZStack {
            PanelBackdrop(close: close)
            ReceivePanel(share: share, close: close)
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { model.receiving = nil }
    }
}

private struct ReceivePanel: View {
    @Environment(AppModel.self) private var model
    let share: ReceivedShare
    let close: () -> Void

    @State private var picked: Set<String> = []
    @State private var project: UUID?
    @State private var newProjectName = ""
    @State private var appeared = false

    private var from: String { share.known?.name ?? share.from.name }
    private var trusted: Bool { share.known?.checked == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.14), in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 8) {
                        Text("From \(from)").font(.headline)
                        if trusted { Chip(text: "Code compared", style: .accent) }
                    }
                    Text(share.made.formatted(date: .abbreviated, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                PanelCloseButton(action: close)
            }
            .padding(.bottom, 12)

            if !trusted {
                Label(share.known == nil
                      ? "Slinky doesn't know this card. Check with \(share.from.name), on a call or in person, that they sent it before you use these. Their code: \(share.from.fingerprint)"
                      : "You haven't compared \(from)'s code yet. Compare it in People before you use these.",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(Color.attention)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(share.items.labeled.enumerated()), id: \.offset) { index, item in
                        if index > 0 { Divider().padding(.leading, 40) }
                        Toggle(isOn: Binding(get: { picked.contains(item.name) }, set: { if $0 { picked.insert(item.name) } else { picked.remove(item.name) } })) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name).font(.body.monospaced().weight(.medium))
                                Text(item.kind).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(height: min(CGFloat(share.items.count) * 48 + 4, 244))
            .background(Color.paper, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1))

            if !share.items.variables.isEmpty {
                Form {
                    Picker("Variables go into", selection: $project) {
                        Text("A new project").tag(UUID?.none)
                        ForEach(model.document.projects) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    if project == nil {
                        TextField("Project name", text: $newProjectName, prompt: Text(share.items.projectName ?? "Project"))
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
                .frame(height: project == nil ? 104 : 64)
                .padding(.horizontal, -18)
            }

            HStack(spacing: 10) {
                EncryptedNote()
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction).glassButton()
                Button(picked.isEmpty ? "Save" : "Save \(picked.count)") {
                    let name = newProjectName.trimmingCharacters(in: .whitespaces)
                    model.saveReceived(share, picked: picked, project: project, newProject: name.isEmpty ? nil : name)
                }
                .keyboardShortcut(.defaultAction)
                .glassProminentButton()
                .disabled(picked.isEmpty)
            }
            .dialogButtons()
            .padding(.top, 14)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 560)
        .glass(in: .rect(cornerRadius: 28))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 14)
        .panelEntrance(appeared)
        .onAppear {
            picked = Set(share.items.names)
            // A project with the same name is the likely home for shared variables.
            if let name = share.items.projectName { project = model.document.projects.first { $0.name == name }?.id }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) { appeared = true }
        }
    }
}

// MARK: Shared projects

struct SharedProjectSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID

    @State private var chosen: Set<UUID> = []
    @State private var folder: URL?
    @State private var working = false
    @State private var adding = false

    private var sync: SharedProjects { .shared }
    private var project: Project? { model.document.projects.first { $0.id == projectID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let project, let sharing = project.sharing {
                members(project, sharing)
            } else {
                start
            }
        }
        .padding(22)
        .frame(width: 540)
        .frame(minHeight: 420)
    }

    // Not shared yet: pick people and the team's folder.
    private var start: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Share \(project?.name ?? "") with Your Team").font(.title3.weight(.semibold))
            Text("Everyone you pick gets the project's variables, and changes anyone makes reach everyone. Slinky keeps an encrypted file in a folder your team already shares, like a shared iCloud Drive or Dropbox folder, and your sync service moves it. Slinky sends nothing anywhere itself.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            PeoplePicker(chosen: $chosen)
            LabeledContent("Team folder") {
                HStack {
                    Text(folder.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "None chosen")
                        .font(.callout.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                    Button("Choose…", action: chooseFolder)
                }
            }
            Text("Each person can open it only on Macs whose cards you added. Folders you linked stay on this Mac. Anyone with the folder can delete or replace the file, so keep a backup of your vault.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                if working { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).glassButton()
                Button("Share Project") {
                    guard let folder else { return }
                    working = true
                    Task {
                        let ok = await sync.start(projectID, with: chosen, in: folder)
                        working = false
                        if ok { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .glassProminentButton()
                .disabled(chosen.isEmpty || folder == nil || working)
            }
            .dialogButtons()
        }
    }

    // Shared: who's in it, the folder, adding and removing.
    private func members(_ project: Project, _ sharing: ProjectSharing) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("People in \(project.name)").font(.title3.weight(.semibold))
            if let problem = sync.problems[projectID] {
                Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(Color.attention).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if sync.needsNewKey.contains(projectID) {
                Button("Open with Touch ID") { Task { await sync.takeNewKey(projectID) } }.glassProminentButton()
            }
            List {
                ForEach(sharing.members, id: \.self) { member in
                    memberRow(member, sharing: sharing)
                }
            }
            .frame(minHeight: 150)
            if adding {
                PeoplePicker(chosen: $chosen, excluding: Set(model.document.people.filter { p in sharing.members.contains { m in m.cards.contains(where: p.has) } }.map(\.id)))
                HStack {
                    Spacer()
                    Button("Cancel") { adding = false; chosen = [] }
                    Button("Add") {
                        Task { await sync.addPeople(chosen, to: projectID); chosen = []; adding = false }
                    }
                    .disabled(chosen.isEmpty)
                }
            }
            LabeledContent("Team folder") {
                if let url = sync.fileURL(for: project) {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                } else {
                    Button("Choose…") {
                        chooseFolder()
                        if let folder { model.open([folder.appendingPathComponent(sharing.fileName)], on: .window) }
                    }
                }
            }
            if let last = sync.lastSynced[projectID] {
                Text("Up to date \(last.formatted(.relative(presentation: .named))).").font(.caption).foregroundStyle(.secondary)
            }
            Text("Removing someone makes a new key for everyone else. They keep what they already saw, so Slinky lists the keys to replace.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Stop Following on This Mac", role: .destructive) { sync.stopSharing(projectID); dismiss() }
                Spacer()
                Button("Add People…") { adding = true }.disabled(adding)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).glassProminentButton()
            }
            .dialogButtons()
        }
    }

    private func memberRow(_ member: SharedMember, sharing: ProjectSharing) -> some View {
        let isMe = model.myCard.map(member.has) ?? false
        let person = model.document.people.first { p in member.cards.contains(where: p.has) }
        let newMacs = person.map { p in p.cards.filter { !member.has($0) } } ?? []
        return HStack(spacing: 8) {
            Text(member.name + (isMe ? " (you)" : "")).fontWeight(.medium)
            if member.cards.count > 1 { Text("\(member.cards.count) Macs").foregroundStyle(.secondary) }
            Spacer()
            if !newMacs.isEmpty {
                Button("Add Their Other Mac") { Task { await sync.addNewMacs(of: member, in: projectID) } }.controlSize(.small)
            }
            if !isMe && sharing.members.count > 1 {
                Button("Remove", role: .destructive) { Task { await sync.remove(member, from: projectID) } }.controlSize(.small)
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose a folder your team shares, like a shared folder in iCloud Drive or Dropbox."
        if panel.runModal() == .OK { folder = panel.url }
    }
}

/// After someone leaves: the secrets they could see, each with a way to make a new one. Names only.
struct RotationChecklistSheet: View {
    @Environment(AppModel.self) private var model
    let checklist: RotationChecklist
    @State private var done: Set<UUID> = []

    private var project: Project? { model.document.projects.first { $0.id == checklist.projectID } }
    private var variables: [Variable] { project?.variables.filter { checklist.variables.contains($0.id) } ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Make New Keys").font(.title3.weight(.semibold))
            Text("\(checklist.person) could see these \(variables.count == 1 ? "key" : "\(variables.count) keys") in \(project?.name ?? "the project"). Removing them can't make anyone forget what they saw, so make new ones on each service and paste them in. Everyone in the project gets the new values.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List(variables) { variable in
                HStack {
                    Toggle(isOn: Binding(get: { done.contains(variable.id) }, set: { if $0 { done.insert(variable.id) } else { done.remove(variable.id) } })) {
                        Text(variable.name).font(.body.monospaced())
                    }
                    .toggleStyle(.checkbox)
                    Spacer()
                    if let url = model.rotationURL(for: variable.iconSubject) {
                        Button("Open Key Page") { NSWorkspace.shared.open(url) }.controlSize(.small)
                    }
                    Button("Paste New Value") {
                        model.selection = .project(checklist.projectID)
                        model.revealVariable = (variable.id, .local)
                    }
                    .controlSize(.small)
                }
            }
            .frame(minHeight: 180)
            HStack {
                Text("\(done.count) of \(variables.count) done").foregroundStyle(.secondary)
                Spacer()
                Button(done.count == variables.count ? "Done" : "Later") { SharedProjects.shared.checklist = nil }
                    .keyboardShortcut(.defaultAction).glassProminentButton()
            }
            .dialogButtons()
        }
        .padding(22)
        .frame(width: 560, height: 480)
    }
}

/// At the top of a shared project, only when something needs the person: the key changed, they were removed,
/// the file is missing, or this Mac hasn't been told where the team folder is.
struct SharedStatusBanner: View {
    @Environment(AppModel.self) private var model
    let project: Project
    @State private var working = false

    private var sync: SharedProjects { .shared }

    var body: some View {
        if let content {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "person.2").foregroundStyle(Color.attention)
                Text(content.text).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let action = content.action {
                    Button(action.title) { run(action.kind) }
                        .disabled(working)
                        .glassButton()
                        .controlSize(.small)
                }
            }
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(cornerRadius: 14)
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private enum Kind { case takeKey, keepCopy, chooseFolder }
    private struct Action { let title: String; let kind: Kind }
    private struct Content { let text: String; let action: Action? }

    private var content: Content? {
        guard project.sharing != nil else { return nil }
        if sync.removed.contains(project.id) {
            return Content(text: "You're no longer in \(project.name). Your copy stays here and stops updating.",
                           action: Action(title: "Keep My Copy", kind: .keepCopy))
        }
        if sync.needsNewKey.contains(project.id) {
            return Content(text: "Someone changed who's in \(project.name), so it has a new key.",
                           action: Action(title: "Open with Touch ID", kind: .takeKey))
        }
        if sync.fileURL(for: project) == nil {
            return Content(text: "\(project.name) is shared through a team folder. Choose where that folder is on this Mac.",
                           action: Action(title: "Choose Folder…", kind: .chooseFolder))
        }
        if let problem = sync.problems[project.id] { return Content(text: problem, action: nil) }
        return nil
    }

    private func run(_ kind: Kind) {
        switch kind {
        case .takeKey:
            working = true
            Task { await sync.takeNewKey(project.id); working = false }
        case .keepCopy:
            sync.stopSharing(project.id)
        case .chooseFolder:
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.message = "Choose the team folder that holds \(project.sharing?.fileName ?? "the shared file")."
            if panel.runModal() == .OK, let folder = panel.url, let name = project.sharing?.fileName {
                model.open([folder.appendingPathComponent(name)], on: .window)
            }
        }
    }
}

extension SharedItems {
    /// Names with what kind of item each is, for the review panel. Never values.
    var labeled: [(name: String, kind: String)] {
        keys.map { ($0.name, $0.provider.map { "Key · \($0)" } ?? "Key or token") }
            + kept.map { ($0.label, $0.kind.title) }
            + codeSets.map { ($0.account, "Recovery codes · \($0.codes.count)") }
            + files.map { ($0.name, "File") }
            + variables.map { ($0.name, "Project variable" + (projectName.map { " · \($0)" } ?? "")) }
    }
}
