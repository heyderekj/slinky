import SlinkyCoreShared
import SwiftUI

extension Detection.Destination {
    var symbol: String {
        switch self {
        case .key: "key.fill"
        case .project: "folder.fill"
        case .codes: "number.square.fill"
        case .kept: "lifepreserver.fill"
        }
    }

    /// One short line under the name on the starter tiles.
    var hint: String {
        switch self {
        case .key: "API keys and access tokens"
        case .project: "Lines from a .env file"
        case .codes: "Backup codes for two-step sign-in"
        case .kept: "Keys that get you back into an account"
        }
    }

    /// Where it ends up, in the sidebar's words.
    var place: String {
        switch self {
        case .key: "Keys & Tokens"
        case .project: "a project"
        case .codes, .kept: "Recovery"
        }
    }
}

/// What sits behind a floating panel: frosted and dimmed. A layer on top, never a blur of the window itself,
/// which changes how the window lays out under the toolbar and makes everything jump.
struct PanelBackdrop: View {
    let close: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(.black.opacity(0.18))
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { close() }
        .accessibilityHidden(true)
    }
}

/// Add Item floats over the window on a soft dim, instead of a sheet.
struct AddItemOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            PanelBackdrop(close: close)
            AddItemPanel(close: close)
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { model.showTuck = false }
    }
}

/// One field: paste anything secret. The value turns into dots the moment it lands (the same motion as
/// the empty state), Slinky says what it looks like and where it goes, and the details are small chips.
/// Values sit on opaque paper inside the glass panel, never on glass.
struct AddItemPanel: View {
    @Environment(AppModel.self) private var model
    let close: () -> Void

    enum ProjectChoice: Hashable { case existing(UUID), new }
    enum Field: Hashable { case input, name, from, projectName }

    @State private var text = ""
    @State private var captured = false
    @State private var revealed = false
    @State private var masked = 0
    @State private var settled = false
    @State private var glow = false
    @State private var destination: Detection.Destination = .key
    @State private var destinationTouched = false
    @State private var name = ""
    @State private var nameTouched = false
    @State private var from = ""
    @State private var showFrom = false
    @State private var project: ProjectChoice = .new
    @State private var newProjectName = ""
    @State private var env: AppEnvironment = .local
    @State private var hasExpiry = false
    @State private var expiry = Calendar.current.date(byAdding: .day, value: 90, to: .now) ?? .now
    @State private var showExpiry = false
    @State private var appeared = false
    @FocusState private var focus: Field?

    private var detection: Detection? { Detector.detect(text) }
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSeed: Bool { detection?.kind == .walletSeed }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Add Item").font(.headline)
                Spacer()
                Keycap("esc")
            }
            .padding(.bottom, 14)

            if captured {
                slab
                    .transition(.asymmetric(insertion: .scale(scale: 0.97).combined(with: .opacity), removal: .opacity))
                if let detection {
                    detectionLine(detection).padding(.top, 12)
                }
                if let duplicate = duplicateNote {
                    Label(duplicate, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                        .transition(.opacity)
                }
                if !isSeed {
                    chips.padding(.top, 12)
                }
            } else {
                input.transition(.opacity)
                starters.padding(.top, 12)
            }

            footer.padding(.top, 18)
        }
        .padding(24)
        .frame(width: 720)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 14)
        .scaleEffect(appeared ? 1 : 0.95)
        .offset(y: appeared ? 0 : 14)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: captured)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: destination)
        .onAppear(perform: setUp)
        .onChange(of: text) { old, new in
            // A paste (many characters at once, or several lines) lands straight away.
            if !captured, new.count - old.count >= 8 || new.contains("\n") { capture() }
            applySuggestions()
        }
    }

    // MARK: Empty: the field

    private var input: some View {
        TextField("", text: $text, prompt: Text("Paste a key, recovery codes or .env lines"), axis: .vertical)
            .textFieldStyle(.plain)
            // The prompt reads as a sentence; what you type reads as code.
            .font(text.isEmpty ? .system(size: 19, weight: .regular) : .system(size: 17, weight: .medium, design: .monospaced))
            .lineLimit(1...5)
            .focused($focus, equals: .input)
            .onSubmit(capture)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
            .background(Color.paper, in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(focus == .input ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.2), lineWidth: 1)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 6) {
                    Keycap("⌘V")
                    Text(text.isEmpty ? "to paste" : "Return when you're done typing")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .padding(14)
            }
            .accessibilityLabel("Value to save")
    }

    /// For typing a value Slinky can't recognize: pick what it is first. Two lines each, by design.
    private var starters: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Or choose what you're adding").font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(Detection.Destination.allCases, id: \.self) { d in
                    Button {
                        destination = d
                        destinationTouched = true
                        focus = .input
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: d.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.title).font(.callout.weight(.semibold)).lineLimit(1)
                                Text(d.hint).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(2, reservesSpace: true)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(TileButtonStyle(selected: destinationTouched && destination == d))
                }
            }
        }
    }

    // MARK: Captured: the slab

    private var slab: some View {
        HStack(alignment: .top, spacing: 14) {
            icon
            VStack(alignment: .leading, spacing: 6) {
                if destination == .project, envLines.count > 1 {
                    Text("\(envLines.count) variables").font(.system(size: 17, weight: .semibold))
                } else if !isSeed {
                    TextField("", text: nameBinding, prompt: Text(namePrompt))
                        .textFieldStyle(.plain)
                        .font(.system(size: 17, weight: .semibold, design: nameIsCode ? .monospaced : .default))
                        .focused($focus, equals: .name)
                }
                preview
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                if !isSeed, !isMultiLine {
                    IconButton(symbol: revealed ? "eye.slash" : "eye", help: revealed ? "Hide" : "Show") { revealed.toggle() }
                }
                IconButton(symbol: "xmark", help: "Clear") { clear() }
            }
        }
        .padding(16)
        .background(isSeed ? Color.orange.opacity(0.1) : Color.paper, in: .rect(cornerRadius: 18))
        .overlay {
            // One quiet glow as the value lands.
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(isSeed ? Color.orange.opacity(0.5) : Color.accentColor.opacity(glow ? 0.7 : 0.18), lineWidth: glow ? 1.5 : 1)
        }
    }

    @ViewBuilder
    private var icon: some View {
        if isSeed {
            symbolTile("hand.raised.fill", tint: .orange)
        } else if let provider = detection?.provider {
            Monogram(text: provider, size: 38)
        } else {
            symbolTile(destination.symbol, tint: .accentColor)
        }
    }

    private func symbolTile(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 38, height: 38)
            .background(tint.opacity(0.14), in: .rect(cornerRadius: 10))
    }

    @ViewBuilder
    private var preview: some View {
        if isSeed {
            Text("This looks like a crypto wallet recovery phrase. For your safety, Slinky doesn't store these.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        } else if destination == .codes {
            let shown = codes.prefix(10)
            VStack(alignment: .leading, spacing: 6) {
                Text("\(codes.count) codes").font(.callout).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .leading), count: 5), spacing: 6) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, code in
                        Text(revealed ? code : Self.dots(code))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 5))
                    }
                }
            }
        } else if envLines.count > 1 {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(envLines.prefix(5), id: \.name) { line in
                    HStack(spacing: 0) {
                        Text(line.name)
                        Text("=••••").foregroundStyle(.tertiary)
                    }
                }
                if envLines.count > 5 {
                    Text("and \(envLines.count - 5) more").foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 12.5, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
        } else {
            Text(revealed ? singleValue : maskedValue)
                .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .contentTransition(.interpolate)
                .lineLimit(revealed ? 3 : 1)
                .truncationMode(.middle)
                .textSelection(.disabled)
        }
    }

    private func detectionLine(_ detection: Detection) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle.magnifyingglass").foregroundStyle(.secondary)
            Text(isSeed ? "Nothing was saved." : detection.label)
            if detection.isLive { Chip(text: "Live", style: .live) }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    // MARK: Chips

    private var chips: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(Detection.Destination.allCases, id: \.self) { d in
                    Button { destination = d; destinationTouched = true } label: { Label(d.title, systemImage: d.symbol) }
                }
            } label: {
                ChipLabel(symbol: destination.symbol, text: destination.title, menu: true)
            }
            .menuStyle(.button)
            .buttonStyle(ChipButtonStyle(selected: true))
            .menuIndicator(.hidden)
            .fixedSize()

            switch destination {
            case .key:
                Button {
                    if !hasExpiry { hasExpiry = true }
                    showExpiry = true
                } label: {
                    ChipLabel(symbol: "calendar", text: hasExpiry ? "Expires \(expiry.formatted(date: .abbreviated, time: .omitted))" : "Add expiry date")
                }
                .buttonStyle(ChipButtonStyle(selected: hasExpiry))
                .popover(isPresented: $showExpiry, arrowEdge: .bottom) {
                    VStack(alignment: .trailing, spacing: 8) {
                        DatePicker("Expires", selection: $expiry, in: Date.now..., displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                        Button("No Expiry Date") { hasExpiry = false; showExpiry = false }
                            .buttonStyle(.link)
                    }
                    .padding(12)
                }
            case .project:
                Menu {
                    ForEach(model.document.projects) { p in
                        Button(p.name) { project = .existing(p.id) }
                    }
                    if !model.document.projects.isEmpty { Divider() }
                    Button("New Project…") { project = .new; focus = .projectName }
                } label: {
                    ChipLabel(symbol: "folder", text: projectTitle, menu: true)
                }
                .menuStyle(.button)
                .buttonStyle(ChipButtonStyle(selected: true))
                .menuIndicator(.hidden)
                .fixedSize()
                if project == .new {
                    ChipField(symbol: "plus", prompt: "Project name", text: $newProjectName)
                        .focused($focus, equals: .projectName)
                }
                Menu {
                    ForEach(AppEnvironment.allCases) { e in Button(e.title) { env = e } }
                } label: {
                    ChipLabel(symbol: "circle.lefthalf.filled", text: env.title, menu: true)
                }
                .menuStyle(.button)
                .buttonStyle(ChipButtonStyle(selected: true))
                .menuIndicator(.hidden)
                .fixedSize()
            case .kept, .codes:
                let prompt = destination == .kept ? "Website or app" : "Username"
                if showFrom || !from.isEmpty {
                    ChipField(symbol: destination == .kept ? "globe" : "person", prompt: prompt, text: $from)
                        .focused($focus, equals: .from)
                } else {
                    Button {
                        showFrom = true
                        focus = .from
                    } label: {
                        ChipLabel(symbol: "plus", text: "Add \(prompt.lowercased())")
                    }
                    .buttonStyle(ChipButtonStyle(selected: false))
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            EncryptedNote()
            Spacer()
            Button("Cancel", action: close)
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.glass)
                .controlSize(.large)
            Button(action: save) {
                HStack(spacing: 8) {
                    Text(captured && !isSeed ? "Save to \(destination.place)" : "Save")
                    Text("↵").font(.callout.weight(.semibold)).opacity(0.6)
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!canSave)
        }
    }

    // MARK: Behavior

    private func setUp() {
        if let id = model.tuckProject {
            project = .existing(id)
            destination = .project
            destinationTouched = true
        } else if case let .project(id)? = model.selection {
            project = .existing(id)
        } else if let first = model.document.projects.first {
            project = .existing(first.id)
        }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) { appeared = true }
        if !model.tuckPrefill.isEmpty {
            text = model.tuckPrefill
            capture()
        } else {
            Task { focus = .input }
        }
    }

    private func capture() {
        guard !trimmed.isEmpty, !captured else { return }
        applySuggestions()
        captured = true
        masked = 0
        settled = false
        focus = isSeed ? nil : (envLines.count > 1 ? nil : .name)
        Task { await land() }
    }

    /// The value turns into dots left to right, then settles into its short form. Reduce Motion: instantly.
    private func land() async {
        let total = middle.count
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, total > 0 {
            withAnimation(.easeOut(duration: 0.25)) { glow = true }
            let step = max(1, total / 28)
            var n = 0
            while n < total {
                n = min(total, n + step)
                withAnimation(.snappy(duration: 0.1)) { masked = n }
                try? await Task.sleep(for: .milliseconds(18))
            }
            try? await Task.sleep(for: .milliseconds(160))
        }
        withAnimation(.smooth(duration: 0.35)) {
            masked = total
            settled = true
            glow = false
        }
    }

    private func clear() {
        text = ""
        captured = false
        revealed = false
        masked = 0
        settled = false
        destinationTouched = false
        nameTouched = false
        name = ""
        from = ""
        showFrom = false
        hasExpiry = false
        focus = .input
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
        guard captured, !trimmed.isEmpty, !isSeed else { return false }
        let hasName = !name.trimmingCharacters(in: .whitespaces).isEmpty
        switch destination {
        case .kept, .key: return hasName
        case .codes: return codes.count >= 2 && hasName
        case .project:
            let hasProject = project != .new || !newProjectName.trimmingCharacters(in: .whitespaces).isEmpty
            return hasProject && (envLines.count > 1 || hasName)
        }
    }

    private func save() {
        guard canSave else { return }
        let label = name.trimmingCharacters(in: .whitespaces)
        switch destination {
        case .kept:
            let kind: KeptKind = detection?.kind == .setupKey ? .setupKey : .recoveryKey
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
        close()
    }

    // MARK: Derived values

    /// "Already saved in Keys & Tokens, as GITHUB_TOKEN." Saving again is allowed; this just says so.
    private var duplicateNote: String? {
        guard captured, !isSeed else { return nil }
        if destination == .codes {
            let places = model.places(ofCodes: codes)
            return places.isEmpty ? nil : "Some of these codes are already saved: \(places.joined(separator: "; "))."
        }
        if envLines.count > 1 {
            let repeated = envLines.filter { !model.places(of: $0.value).isEmpty }.count
            guard repeated > 0 else { return nil }
            return repeated == envLines.count
                ? "All of these values are already saved in Slinky."
                : "\(repeated) of these values \(repeated == 1 ? "is" : "are") already saved in Slinky."
        }
        let places = model.places(of: singleValue)
        guard let first = places.first else { return nil }
        return "Already saved in \(first)" + (places.count > 1 ? " and \(places.count - 1) more \(places.count == 2 ? "place" : "places")." : ".")
    }

    private var nameBinding: Binding<String> {
        Binding(get: { name }, set: { name = $0; nameTouched = true })
    }

    private var namePrompt: String {
        switch destination {
        case .key: "Name, like GITHUB_TOKEN"
        case .project: "Variable name, like RESEND_API_KEY"
        case .codes: "Account, like GitHub"
        case .kept: "Name, like Apple Account recovery key"
        }
    }

    private var nameIsCode: Bool { destination == .key || destination == .project }

    private var projectTitle: String {
        if case let .existing(id) = project, let p = model.document.projects.first(where: { $0.id == id }) { return p.name }
        return "New Project"
    }

    private var envLines: [DotEnvLine] {
        if case let .envLines(lines)? = detection?.kind { return lines }
        return []
    }

    private var isMultiLine: Bool { envLines.count > 1 || destination == .codes }

    /// The single value being saved (for a one-line KEY=value paste, just the value).
    private var singleValue: String {
        envLines.count == 1 ? envLines[0].value : trimmed
    }

    private var codes: [String] {
        if case let .recoveryCodes(found)? = detection?.kind { return found }
        return RecoveryCodes.extract(text)
    }

    /// The value splits into a recognizable head (like "sk_live_"), a middle that turns into dots, and the last 4.
    private var parts: (head: String, middle: String, tail: String) {
        let v = singleValue
        guard v.count > 10 else { return ("", v, "") }
        let head = v.prefix(12)
        let cut = head.lastIndex(where: { $0 == "_" || $0 == "-" }).map { head.distance(from: head.startIndex, to: $0) + 1 } ?? 0
        return (String(v.prefix(cut)), String(v.dropFirst(cut).dropLast(4)), String(v.suffix(4)))
    }

    private var middle: String { parts.middle }

    private var maskedValue: String {
        let p = parts
        if settled { return p.head + String(repeating: "•", count: min(12, max(4, p.middle.count))) + p.tail }
        let mid = p.middle.enumerated().map { i, ch in i < masked ? "•" : String(ch) }.joined()
        return p.head + mid + p.tail
    }

    /// Codes keep their shape: "a1b2c-3d4e5" → "•••••-•••••".
    private static func dots(_ code: String) -> String {
        String(code.map { $0 == "-" || $0 == " " ? $0 : "•" })
    }
}

// MARK: Small parts

/// The reassurance in every panel footer. Readable, not fine print.
struct EncryptedNote: View {
    var body: some View {
        Label("Encrypted on this Mac", systemImage: "lock.shield")
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

struct Keycap: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.5))
    }
}

struct ChipLabel: View {
    let symbol: String
    let text: String
    var menu = false
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
            Text(text)
            if menu { Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .bold)).opacity(0.6) }
        }
    }
}

/// A starter tile: quiet until hovered, tinted when chosen.
struct TileButtonStyle: ButtonStyle {
    var selected: Bool
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.primary)
            .padding(12)
            .background(fill(configuration.isPressed), in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(selected ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(hovering ? 0.3 : 0.18), lineWidth: 1))
            .contentShape(.rect(cornerRadius: 14))
            .onHover { hovering = $0 }
    }

    private func fill(_ pressed: Bool) -> Color {
        if selected { return Color.accentColor.opacity(pressed ? 0.24 : 0.15) }
        return Color.secondary.opacity(pressed ? 0.14 : hovering ? 0.09 : 0.05)
    }
}

/// A capsule chip: tinted when it holds a choice, quiet when it's an option you can add.
struct ChipButtonStyle: ButtonStyle {
    var selected: Bool
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(fill(configuration.isPressed), in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.22),
                                            style: StrokeStyle(lineWidth: 1, dash: selected ? [] : [3, 2.5])))
            .contentShape(Capsule())
            .onHover { hovering = $0 }
    }

    private func fill(_ pressed: Bool) -> Color {
        if selected { return Color.accentColor.opacity(pressed ? 0.26 : hovering ? 0.2 : 0.14) }
        return Color.secondary.opacity(pressed ? 0.16 : hovering ? 0.1 : 0)
    }
}

/// A chip you type into, for the one-line details (website, username, new project name).
struct ChipField: View {
    let symbol: String
    let prompt: String
    @Binding var text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            TextField("", text: $text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .frame(width: 150)
        }
        .font(.callout)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.1), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1))
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
                .frame(width: 26, height: 26)
                .background(Color.secondary.opacity(hovering ? 0.14 : 0), in: Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
