import SlinkyCoreShared
import SwiftUI

/// The folder review's changes, one section per environment: what's new and what changed, each with a checkbox,
/// then quiet lines for what's the same and what only Slinky has. Peeks only, never whole values.
struct FolderReviewChanges: View {
    let changes: FolderChanges
    @Binding var picks: FolderChanges.Picks
    @Binding var expanded: Set<AppEnvironment>
    let isNew: Bool

    private var environments: [AppEnvironment] {
        AppEnvironment.allCases.filter { env in changes.changes.contains { $0.environment == env } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isNew ? "Variables" : "Changes").font(.headline).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(environments) { env in
                    let rows = moving(in: env)
                    if !rows.isEmpty { section(env, rows) }
                }
                if environments.allSatisfy({ moving(in: $0).isEmpty }) {
                    Text(isNew ? "These files have no variables yet." : "Nothing to update. Everything in these files is already in Slinky.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }
            .card(cornerRadius: 14)
            unchanged
            onlyInSlinky
        }
    }

    // MARK: Sections

    /// New and changed rows, and rows where files disagree (so the other value can be picked).
    private func moving(in env: AppEnvironment) -> [EnvChange] {
        changes.changes.filter { c in
            c.environment == env && ([.new, .changed].contains(changes.status(of: c, picks)) || (c.isConflict && c.current != nil))
        }
    }

    private func section(_ env: AppEnvironment, _ rows: [EnvChange]) -> some View {
        let open = Binding(get: { expanded.contains(env) }, set: { if $0 { expanded.insert(env) } else { expanded.remove(env) } })
        let allOn = rows.allSatisfy { picks.rows.contains($0.id) }
        return DisclosureGroup(isExpanded: open) {
            VStack(spacing: 0) {
                ForEach(rows) { row($0) }
            }
            .padding(.bottom, 4)
        } label: {
            HStack(spacing: 6) {
                Text(env.title).font(.body.weight(.semibold))
                Text("· " + sectionCaption(env, rows)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 8)
                Button(allOn ? "Select None" : "Select All") {
                    for r in rows { if allOn { picks.rows.remove(r.id) } else { picks.rows.insert(r.id) } }
                }
                .buttonStyle(.borderless)
                .font(.subheadline)
            }
            .contentShape(.rect)
            .onTapGesture { withAnimation(.snappy) { open.wrappedValue.toggle() } }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func sectionCaption(_ env: AppEnvironment, _ rows: [EnvChange]) -> String {
        let files = rows.flatMap(\.offers).map(\.source).uniqued()
        let new = rows.filter { changes.status(of: $0, picks) == .new }.count
        let changed = rows.filter { changes.status(of: $0, picks) == .changed }.count
        let counts = [(new, "new"), (changed, "changed")].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }.joined(separator: ", ")
        let from = files.isEmpty ? "" : "from " + files.prefix(2).joined(separator: ", ") + (files.count > 2 ? " and \(files.count - 2) more" : "")
        return [from, counts].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: Rows

    private func row(_ c: EnvChange) -> some View {
        let on = picks.rows.contains(c.id)
        let offer = c.offer(picking: picks.sources[c.id])
        let status = changes.status(of: c, picks)
        return HStack(spacing: 10) {
            Toggle("Import \(c.name)", isOn: Binding(get: { on }, set: { if $0 { picks.rows.insert(c.id) } else { picks.rows.remove(c.id) } }))
                .toggleStyle(.checkbox)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 1) {
                Text(c.name).font(.body.monospaced().weight(.semibold)).lineLimit(1).truncationMode(.middle)
                Text(caption(c, offer, status)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            chip(c, status)
            Text(peek(c, offer, status))
                .font(.callout.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel(offer.map { $0.value.isEmpty ? "Empty value" : "Hidden value, ends in \(String($0.value.suffix(4)))" } ?? "")
        }
        .padding(.vertical, 5)
        .opacity(on ? 1 : 0.55)
    }

    private func caption(_ c: EnvChange, _ offer: EnvChange.Offer?, _ status: EnvChange.Status) -> String {
        guard let offer else { return "" }
        if offer.value.isEmpty { return "Empty in \(offer.source)" }
        switch status {
        case .new where c.variableExists: return "Adds a \(c.environment.title) value · from \(offer.source)"
        case .changed: return "Replaces the value in Slinky · from \(offer.source)"
        case .same: return "The same as in Slinky · from \(offer.source)"
        default: return "From \(offer.source)"
        }
    }

    @ViewBuilder
    private func chip(_ c: EnvChange, _ status: EnvChange.Status) -> some View {
        if c.isConflict {
            // Files disagree: pick which one's value to use. The more specific file is picked to start.
            Menu {
                ForEach(c.offers, id: \.source) { offer in
                    Button {
                        picks.sources[c.id] = offer.source
                        picks.rows.insert(c.id)
                    } label: {
                        Text("\(offer.source) · \(offer.value.isEmpty ? "empty" : Peek.of(offer.value))")
                    }
                }
            } label: {
                Chip(text: "\(c.offers.count) values", style: .warn)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("These files set different values. Click to choose which one to use.")
        } else if status == .new {
            Chip(text: "New", style: .accent)
        } else if status == .changed {
            Chip(text: "Changed", style: .warn)
        }
    }

    private func peek(_ c: EnvChange, _ offer: EnvChange.Offer?, _ status: EnvChange.Status) -> String {
        guard let offer else { return "" }
        let new = offer.value.isEmpty ? "empty" : Peek.of(offer.value)
        if status == .changed, let current = c.current { return (current.isEmpty ? "empty" : Peek.of(current)) + " → " + new }
        return new
    }

    // MARK: Quiet lines

    /// Names the folder has with the same values as Slinky: listed, not offered.
    @ViewBuilder
    private var unchanged: some View {
        let compared = Set(changes.changes.map(\.environment))
        let byName = Dictionary(grouping: changes.changes.filter { $0.status() != .onlyInSlinky }, by: \.name)
        let same = byName.filter { $0.value.allSatisfy { changes.status(of: $0, picks) == .same && !$0.isConflict } }
            .map { name, rows in (name, rows.map(\.environment)) }
            .sorted { $0.0 < $1.0 }
        if !same.isEmpty {
            DisclosureGroup("\(same.count) unchanged") {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(same, id: \.0) { name, envs in
                        HStack(spacing: 6) {
                            Text(name).font(.subheadline.monospaced())
                            Text(compared.count > 1 && Set(envs) == compared ? "· All environments"
                                                                              : "· " + envs.map(\.title).joined(separator: ", "))
                                .font(.subheadline).foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    /// Names Slinky has that these files don't: they stay as they are.
    @ViewBuilder
    private var onlyInSlinky: some View {
        let names = changes.changes.filter { $0.status() == .onlyInSlinky }.map(\.name).uniqued()
        if !names.isEmpty {
            DisclosureGroup("\(names.count) only in Slinky. They stay as they are.") {
                Text(names.joined(separator: ", "))
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}
