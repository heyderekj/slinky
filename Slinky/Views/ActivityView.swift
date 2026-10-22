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
                            ForEach(entries) { row($0) }
                        } header: {
                            Text(Self.dayTitle(day))
                        }
                    }
                }
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

    private func row(_ e: ActivityEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol(e.action))
                .foregroundStyle(e.action == .guarded || e.action == .leakFound ? Color.attention : Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(sentence(e)).lineLimit(2)
                if !e.detail.isEmpty {
                    Text(e.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(e.date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.vertical, 3)
    }

    private func names(_ e: ActivityEntry) -> String {
        switch e.names.count {
        case 0: "nothing"
        case 1: e.names[0]
        case 2, 3: e.names.joined(separator: ", ")
        default: "\(e.names.prefix(2).joined(separator: ", ")) and \(e.names.count - 2) more"
        }
    }

    private func sentence(_ e: ActivityEntry) -> String {
        let who = e.actor == "You" ? "You" : e.actor
        switch e.action {
        case .copied: return "\(who) copied \(names(e))"
        case .codeUsed: return "\(who) used a \(names(e))"
        case .ran: return "\(who) ran a command with \(names(e))"
        case .exported: return "\(who) loaded \(names(e)) into a shell"
        case .xcconfig: return "\(who) used \(names(e)) for a build"
        case .requested: return "\(who) asked for \(names(e))"
        case .guarded: return "A commit with \(names(e)) was stopped"
        case .leakFound: return "\(names(e)) found outside Slinky"
        case .pushed: return "\(who) sent \(names(e)) to a host"
        case .notarized: return "\(who) saved a notarytool profile from \(names(e))"
        case .rotated: return "\(who) replaced \(names(e)) with a new one"
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
