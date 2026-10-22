import SlinkyCoreShared
import SwiftUI

/// The details pane with several things selected: how many, and what can be done to all of them at once.
struct MultiSelectionPane: View {
    let count: Int
    let noun: String
    /// What the AI agents picker shows: the shared rule, or nil when they differ (or don't apply).
    var policy: AgentPolicy?
    var setPolicy: ((AgentPolicy) -> Void)?
    var makePublic: (() -> Void)?
    var makeSecret: (() -> Void)?
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "square.stack.3d.up")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(count) \(noun) selected").font(.title3.weight(.semibold))
                    Text("Changes here apply to all of them.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Form {
                if let setPolicy {
                    Section {
                        Picker("AI agents", selection: Binding(get: { policy ?? .agentsCanUse }, set: setPolicy)) {
                            ForEach(AgentPolicy.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    } footer: {
                        if policy == nil { Text("They're set differently now. Picking one sets all of them.").font(.caption) }
                    }
                }
                if makePublic != nil || makeSecret != nil {
                    Section {
                        if let makeSecret { Button("Make Them Secrets", action: makeSecret) }
                        if let makePublic { Button("Make Them Public Settings", action: makePublic) }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack {
                Button("Delete \(count) \(noun.prefix(1).uppercased() + noun.dropFirst())", role: .destructive, action: delete)
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.danger)
                    .help("Move them to Recently Deleted. Undo puts them back.")
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
}
