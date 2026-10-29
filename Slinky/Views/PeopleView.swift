import AppKit
import SlinkyCoreShared
import SlinkyCoreVault
import SwiftUI

/// People: your card and the people you share with, in the main window (the footer's people button, ⌘8).
/// One job: get cards swapped and codes compared, so sharing works.
struct PeopleView: View {
    @Environment(AppModel.self) private var model

    private var others: [Person] { model.document.people.filter { !$0.isMe } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let card = model.myCard {
                    YourCard(card: card)
                } else {
                    Text("This Mac couldn't make a sharing card. Sharing needs the Secure Enclave, which every Apple silicon Mac has.")
                        .foregroundStyle(.secondary)
                }
                if others.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No one yet").font(.headline)
                        Text("Send your card to someone you work with, and open theirs when it arrives (or paste it here with ⌘V). Then you can share keys, or a whole project, with each other.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Add Someone's Card…") { model.beginAddPerson() }
                            .padding(.top, 4)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("People").font(.headline).foregroundStyle(.secondary)
                        VStack(spacing: 0) {
                            ForEach(Array(others.enumerated()), id: \.element.id) { index, person in
                                if index > 0 { Divider().padding(.leading, 56) }
                                PersonRow(person: person)
                            }
                        }
                        .background(Color.paper, in: .rect(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1))
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .screenTitle("People", subtitle: others.isEmpty ? "" : counted(others.count, "person"))
    }
}

/// This Mac's card: who you are to the people you share with, the code they compare, and how to send it.
private struct YourCard: View {
    @Environment(AppModel.self) private var model
    let card: PersonCard
    @State private var name = ""
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Monogram(text: card.name, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Your name", text: $name)
                        .textFieldStyle(.plain)
                        .font(.title3.weight(.semibold))
                        .onSubmit { model.renameMe(name) }
                        // Saves a moment after typing stops: no Return needed (clicking a button on the Mac
                        // doesn't take focus from the field, so "save when you leave it" never fired).
                        .task(id: name) {
                            try? await Task.sleep(for: .milliseconds(700))
                            if !Task.isCancelled { model.renameMe(name) }
                        }
                    Text("Your card · this Mac").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Your code").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                CodeText(code: card.fingerprint)
            }
            Text("Send your card to the people you work with. It holds this Mac's public keys only, so it can't open anything. When you add each other, compare codes on a call or in person.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if let url = model.myCardFile() {
                    ShareLink(item: url) { Label("Send Your Card…", systemImage: "square.and.arrow.up") }
                        .glassProminentButton()
                }
                Button(copied ? "Copied" : "Copy as Text") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(card.text, forType: .string)
                    copied = true
                }
                .glassButton()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(cornerRadius: 22)
        .onAppear { if name.isEmpty { name = card.name } }
    }
}

private struct PersonRow: View {
    @Environment(AppModel.self) private var model
    let person: Person

    var body: some View {
        HStack(spacing: 12) {
            Monogram(text: person.name, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name).fontWeight(.semibold)
                Text(person.cards.count > 1 ? "\(person.cards.count) Macs" : "1 Mac")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if person.checked {
                Chip(text: "Code compared", style: .accent)
            } else {
                Button("Compare Code…") { model.beginAddPerson(comparing: person) }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Compare Code…") { model.beginAddPerson(comparing: person) }
            Divider()
            Button("Remove \(person.name)", role: .destructive) { model.removePerson(person.id) }
        }
    }
}

/// A code in big, evenly spaced groups, easy to read aloud.
struct CodeText: View {
    let code: String
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: size * 0.6) {
            ForEach(code.split(separator: "-").map(String.init), id: \.self) { group in
                Text(group)
            }
        }
        .font(.system(size: size, weight: .semibold, design: .monospaced))
        // One element read as one code (a label on the group alone sent accessibility round in circles).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Code \(code.replacingOccurrences(of: "-", with: " "))")
    }
}

// MARK: Adding someone

/// A card being added (opened, dropped, pasted) or a known person whose code is being compared.
struct AddPersonDraft: Identifiable, Equatable {
    let id = UUID()
    var card: PersonCard?
    /// Comparing the code of someone already in People.
    var person: UUID?
}

struct AddPersonOverlay: View {
    @Environment(AppModel.self) private var model
    let draft: AddPersonDraft

    var body: some View {
        ZStack {
            PanelBackdrop(close: close)
            AddPersonPanel(draft: draft, close: close)
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { model.addingPerson = nil }
    }
}

private struct AddPersonPanel: View {
    @Environment(AppModel.self) private var model
    let draft: AddPersonDraft
    let close: () -> Void

    @State private var pasted = ""
    @State private var card: PersonCard?
    @State private var appeared = false

    private var existing: Person? { draft.person.flatMap { id in model.document.people.first { $0.id == id } } }
    /// Someone already in People with this name: maybe their new Mac.
    private var sameName: Person? {
        guard let card, existing == nil else { return nil }
        return model.document.people.first { !$0.isMe && !$0.has(card) && $0.name.caseInsensitiveCompare(card.name) == .orderedSame }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(existing.map { "Compare \($0.name)'s Code" } ?? (card.map { "Add \($0.name)" } ?? "Add Someone")).font(.headline)
                Spacer()
                PanelCloseButton(action: close)
            }

            if let existing {
                compare(name: existing.name, codes: existing.cards.map(\.fingerprint))
            } else if let card {
                if model.document.me?.has(card) == true {
                    Text("That's your own card. Send it to someone else, and add theirs.").foregroundStyle(.secondary)
                } else if model.document.person(for: card) != nil {
                    Text("\(card.name) is already in People.").foregroundStyle(.secondary)
                } else {
                    compare(name: card.name, codes: [card.fingerprint])
                }
            } else {
                paste
            }
        }
        .padding(20)
        .frame(width: 520)
        .glass(in: .rect(cornerRadius: 28))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 14)
        .panelEntrance(appeared)
        .onAppear {
            card = draft.card
            withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) { appeared = true }
        }
    }

    private var paste: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste the card they sent you, or open the card file.")
                .foregroundStyle(.secondary)
            TextField("Their card", text: $pasted, prompt: Text("slinky-card:v1:…"), axis: .vertical)
                .lineLimit(3...5)
                .font(.callout.monospaced())
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color.paper, in: .rect(cornerRadius: 14))
                .onChange(of: pasted) { if let found = PersonCard(text: pasted) { withAnimation(.smooth) { card = found } } }
            if !pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, PersonCard(text: pasted) == nil {
                Text("That isn't a Slinky card. A card starts with slinky-card:v1:").font(.callout).foregroundStyle(Color.attention)
            }
            HStack {
                Button("Open a Card File…", action: openFile).glassButton()
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction).glassButton()
            }
            .dialogButtons()
        }
    }

    /// The code, big, with the two answers. Matching marks them checked; not matching adds nothing.
    private func compare(name: String, codes: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(codes.count > 1 ? "Codes for \(name)'s Macs" : "\(name)'s code").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(codes, id: \.self) { CodeText(code: $0, size: 26) }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.paper, in: .rect(cornerRadius: 16))
            Text("On a call or in person, ask \(name) to read you the code under Your Card in their People. It should match exactly. If it doesn't, someone else's card may have been sent in their name.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let sameName {
                Button("This is \(sameName.name)'s other Mac") {
                    if let card { model.addCard(card, to: sameName.id) }
                    close()
                }
                .buttonStyle(.link)
            }
            HStack(spacing: 10) {
                if existing == nil {
                    Button("Add Without Comparing") { add(checked: false) }.buttonStyle(.link)
                }
                Spacer()
                Button("It Doesn't Match", action: close).keyboardShortcut(.cancelAction).glassButton()
                Button("It Matches") { add(checked: true) }
                    .keyboardShortcut(.defaultAction)
                    .glassProminentButton()
            }
            .dialogButtons()
        }
    }

    private func add(checked: Bool) {
        if let existing {
            model.setChecked(existing.id, checked)
            if checked { model.show("\(existing.name)'s code matches.") }
        } else if let card {
            model.addCard(card, checked: checked)
        }
        close()
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.message = "Choose the card someone sent you (a .slinkycard file)."
        guard panel.runModal() == .OK, let url = panel.url, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        pasted = text
    }
}
