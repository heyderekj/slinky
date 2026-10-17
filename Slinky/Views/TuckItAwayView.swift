import SlinkyCoreShared
import SwiftUI

/// One paste, the right drawer. Reads what you paste and suggests where it goes.
struct TuckItAwayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    enum ProjectChoice: Hashable { case existing(UUID), new }

    @State private var text = ""
    @State private var destination: Detection.Destination = .kept
    @State private var destinationTouched = false
    @State private var name = ""
    @State private var nameTouched = false
    @State private var from = ""
    @State private var project: ProjectChoice = .new
    @State private var newProjectName = ""
    @State private var env: AppEnvironment = .local
    @State private var hasExpiry = false
    @State private var expiry = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now

    private var detection: Detection? { Detector.detect(text) }
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Tuck It Away").font(.title3.weight(.bold))
                Spacer()
                Text("Paste anything. Slinky figures out where it goes.").font(.callout).foregroundStyle(.secondary)
            }

            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 96)
                .background(.background.secondary, in: .rect(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Paste a key, a block of codes, a KEY=value line…")
                            .font(.system(size: 13)).foregroundStyle(.tertiary)
                            .padding(.horizontal, 14).padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
                .accessibilityLabel("Value to tuck away")

            if let detection {
                Label(detection.label, systemImage: detection.kind == .walletSeed ? "hand.raised.fill" : "sparkle.magnifyingglass")
                    .font(.callout)
                    .foregroundStyle(detection.kind == .walletSeed ? Color.orange : Color.primary)
                    .transition(.opacity)
            }

            if detection?.kind != .walletSeed {
                Picker("Goes in", selection: Binding(get: { destination }, set: { destination = $0; destinationTouched = true })) {
                    ForEach(Detection.Destination.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                fields
            }

            HStack {
                Text("Values are encrypted the moment you save. Nothing is written to disk in plain text.")
                    .font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Tuck It Away") { save() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(22)
        .frame(width: 600)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: destination)
        .onAppear {
            text = model.tuckPrefill
            if let id = model.tuckProject {
                project = .existing(id)
                destination = .project
                destinationTouched = true
            } else if case let .project(id)? = model.selection {
                project = .existing(id)
            } else if let first = model.document.projects.first {
                project = .existing(first.id)
            }
            applySuggestions()
        }
        .onChange(of: text) { applySuggestions() }
    }

    @ViewBuilder
    private var fields: some View {
        Form {
            switch destination {
            case .kept:
                TextField("Label", text: nameBinding, prompt: Text("Apple ID recovery key"))
                TextField("From", text: $from, prompt: Text("Where it came from, optional"))
            case .key:
                TextField("Name", text: nameBinding, prompt: Text("GITHUB_TOKEN"))
                Toggle("Expires", isOn: $hasExpiry)
                if hasExpiry { DatePicker("On", selection: $expiry, displayedComponents: .date) }
            case .project:
                Picker("Project", selection: $project) {
                    ForEach(model.document.projects) { Text($0.name).tag(ProjectChoice.existing($0.id)) }
                    Divider()
                    Text("New project…").tag(ProjectChoice.new)
                }
                if project == .new { TextField("Project name", text: $newProjectName, prompt: Text("harvous")) }
                Picker("Environment", selection: $env) {
                    ForEach(AppEnvironment.allCases) { Text($0.title).tag($0) }
                }
                if envLines.count > 1 {
                    LabeledContent("Variables", value: "\(envLines.count): " + envLines.prefix(4).map(\.name).joined(separator: ", ") + (envLines.count > 4 ? "…" : ""))
                } else {
                    TextField("Name", text: nameBinding, prompt: Text("RESEND_API_KEY"))
                }
            case .codes:
                TextField("Account", text: nameBinding, prompt: Text("GitHub"))
                TextField("Username", text: $from, prompt: Text("Optional"))
                LabeledContent("Codes found", value: "\(codes.count)")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(height: formHeight)
    }

    private var formHeight: CGFloat {
        switch destination {
        case .kept: 120
        case .key: hasExpiry ? 160 : 120
        case .project: 190
        case .codes: 160
        }
    }

    private var nameBinding: Binding<String> {
        Binding(get: { name }, set: { name = $0; nameTouched = true })
    }

    private var envLines: [DotEnvLine] {
        if case let .envLines(lines)? = detection?.kind { return lines }
        return []
    }

    /// The single value being saved (for a one-line KEY=value paste, just the value).
    private var singleValue: String {
        envLines.count == 1 ? envLines[0].value : trimmed
    }

    private var codes: [String] {
        if case let .recoveryCodes(found)? = detection?.kind { return found }
        return RecoveryCodes.extract(text)
    }

    private func applySuggestions() {
        guard let detection else { return }
        if !destinationTouched { destination = detection.destination }
        if !nameTouched {
            switch detection.destination {
            case .codes: name = detection.provider ?? name
            default: name = detection.suggestedName ?? (envLines.count == 1 ? envLines[0].name : name)
            }
        }
    }

    private var canSave: Bool {
        guard !trimmed.isEmpty, detection?.kind != .walletSeed else { return false }
        switch destination {
        case .kept: return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .key: return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .codes: return codes.count >= 2 && !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .project:
            let hasProject = project != .new || !newProjectName.trimmingCharacters(in: .whitespaces).isEmpty
            return hasProject && (envLines.count > 1 || !name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func save() {
        let label = name.trimmingCharacters(in: .whitespaces)
        switch destination {
        case .kept:
            let kind: KeptKind = switch detection?.kind {
            case .recoveryKey?: .recoveryKey
            case .setupKey?: .setupKey
            default: .other
            }
            model.addKept(KeptItem(label: label, kind: kind, from: from.isEmpty ? nil : from, value: singleValue))
        case .key:
            model.addKey(Key(name: label, value: singleValue, provider: detection?.provider,
                             isLive: detection?.isLive ?? false, expires: hasExpiry ? expiry : nil))
        case .codes:
            model.addCodeSet(CodeSet(account: label, username: from.isEmpty ? nil : from, codes: codes))
        case .project:
            let projectID: UUID
            switch project {
            case let .existing(id): projectID = id
            case .new: projectID = model.createProject(name: newProjectName.trimmingCharacters(in: .whitespaces))
            }
            let lines = envLines.count > 1 ? envLines : [DotEnvLine(name: label, value: singleValue)]
            model.addVariables(lines, to: projectID, env: env)
        }
        dismiss()
    }
}
