import SlinkyCoreShared
import SwiftUI

/// What was copied or used, when, and by whom. Names only: never a value. Kept inside the vault.
struct ActivityView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmClear = false

    private var days: [(Date, [ActivityEntry])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: model.document.log) { cal.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!) }
    }

    var body: some View {
        Group {
            if model.document.log.isEmpty {
                ContentUnavailableView("No Activity Yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("Copies, runs and agent requests show up here, by name."))
            } else {
                List {
                    ForEach(days, id: \.0) { day, entries in
                        Section {
                            dayTitle(day)
                            ForEach(entries) { row($0) }
                        }
                    }
                }
                // Day titles are plain rows, like the library's group titles. As section headers they stuck to
                // the top while scrolling, and macOS drew its own edge line there on top of the header's.
                .listStyle(.inset)
            }
        }
        .screenTitle("Activity", subtitle: model.document.log.isEmpty ? "" : counted(model.document.log.count, "event"))
        .toolbar {
            if !model.document.log.isEmpty, !model.lockedChrome {
                ToolbarItem {
                    Button("Clear") { confirmClear = true }.help("Clear the activity history")
                }
            }
        }
        .confirmationDialog("Clear all activity?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { model.clearActivity() }
        } message: {
            Text("Items stay. Only the history of copies and uses goes.")
        }
    }

    private func dayTitle(_ day: Date) -> some View {
        Text(Self.dayTitle(day))
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .listRowSeparator(.hidden)
            .accessibilityAddTraits(.isHeader)
    }

    /// One thing that happened: what kind (a tinted tile), a sentence with the names in code type, any detail
    /// under it, and the time. Room to breathe, like the library's rows.
    private func row(_ e: ActivityEntry) -> some View {
        let warn = e.action == .guarded || e.action == .leakFound
        let tint = warn ? Color.attention : Color.accentColor
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol(e.action))
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: .rect(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                sentence(e)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !e.detail.isEmpty {
                    Text(e.detail).font(.callout).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                }
            }
            .padding(.top, 6)
            .layoutPriority(1)
            Spacer(minLength: 8)
            Text(e.date.formatted(date: .omitted, time: .shortened))
                .font(.callout).foregroundStyle(.tertiary).monospacedDigit()
                .padding(.top, 7)
                .fixedSize()
        }
        .padding(.vertical, 8)
        // Click a line to go to what it's about.
        .contentShape(.rect)
        .onTapGesture { if !model.reveal(e) { model.show("That item isn't in Slinky any more.", style: .info) } }
        .help("Show it")
        .accessibilityAddTraits(.isButton)
    }

    private func names(_ e: ActivityEntry) -> String {
        switch e.names.count {
        case 0: "nothing"
        case 1: e.names[0]
        case 2, 3: e.names.joined(separator: ", ")
        default: "\(e.names.prefix(2).joined(separator: ", ")) and \(e.names.count - 2) more"
        }
    }

    /// The names in code type, with "and 3 more" left as words.
    private func codeNames(_ e: ActivityEntry) -> Text {
        let code = { (s: String) in Text(s).font(.system(.body, design: .monospaced)).fontWeight(.medium) }
        guard e.names.count > 3 else { return code(names(e)) }
        return code(e.names.prefix(2).joined(separator: ", ")) + Text(" and \(e.names.count - 2) more")
    }

    /// The sentence, with the names in code type so they stand out from the words around them.
    private func sentence(_ e: ActivityEntry) -> Text {
        let who = e.actor == "You" ? "You" : e.actor
        let n = codeNames(e)
        switch e.action {
        case .copied: return Text("\(who) copied ") + n
        case .codeUsed: return Text("\(who) used a ") + Text(names(e)).fontWeight(.medium)   // "a GitHub recovery code": words, not a name
        case .ran: return Text("\(who) ran a command with ") + n
        case .exported: return Text("\(who) loaded ") + n + Text(" into a shell")
        case .xcconfig: return Text("\(who) used ") + n + Text(" for a build")
        case .requested: return Text("\(who) asked for ") + n
        case .guarded: return Text("A commit with ") + n + Text(" was stopped")
        case .leakFound: return n + Text(" found outside Slinky")
        case .pushed: return Text("\(who) sent ") + n + Text(" to a host")
        case .notarized: return Text("\(who) saved a notarytool profile from ") + n
        case .rotated: return Text("\(who) replaced ") + n + Text(" with a new one")
        case .imported: return Text("\(who) imported ") + n
        case .other: return n
        }
    }

    private func symbol(_ a: ActivityEntry.Action) -> String {
        switch a {
        case .copied: "doc.on.doc"
        case .codeUsed: "number.square"
        case .ran: "terminal"
        case .exported: "chevron.left.forwardslash.chevron.right"
        case .xcconfig: "hammer"
        case .requested: "hand.raised"
        case .guarded: "hand.raised.slash"
        case .leakFound: "exclamationmark.triangle"
        case .pushed: "icloud.and.arrow.up"
        case .notarized: "checkmark.seal"
        case .rotated: "arrow.triangle.2.circlepath"
        case .imported: "square.and.arrow.down"
        case .other: "clock"
        }
    }
}

extension ActivityView {
    /// Today, Yesterday, then the weekday for this week, then the date: one heading per day, and it never changes
    /// while you look at it ("14 hours ago" did, and older days ran together as "Last week").
    static func dayTitle(_ day: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: calendar.startOfDay(for: now)).day ?? 0
        if days < 7 { return day.formatted(.dateTime.weekday(.wide)) }
        let sameYear = calendar.isDate(day, equalTo: now, toGranularity: .year)
        return sameYear ? day.formatted(.dateTime.weekday(.wide).month(.wide).day())
                        : day.formatted(.dateTime.month(.wide).day().year())
    }
}
