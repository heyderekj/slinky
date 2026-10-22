import SlinkyCoreShared
import SwiftUI

/// Project › Share › Send to Host…: see exactly which names go where, then send after Touch ID.
struct HostPushSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID
    @State private var host: HostPush.Host = .vercel
    @State private var env: AppEnvironment = .production
    @State private var target = ""
    @State private var chosen: Set<String> = []
    @State private var remote: Set<String>?
    @State private var working = false
    @State private var message: String?

    private var project: Project? { model.document.projects.first { $0.id == projectID } }
    private var folder: String? { project?.folders.first }

    /// Variables with a value in the chosen environment.
    private var names: [String] {
        (project?.variables ?? []).filter { $0.value(in: env) != nil }.map(\.name).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Send \(project?.name ?? "") to a Host").font(.title3.weight(.semibold))
            Text("Slinky uses the host's own command-line tool, signed in as you. Values go to that service; you'll see which ones before anything is sent.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            Form {
                Picker("Host", selection: $host) {
                    ForEach(HostPush.Host.allCases) { Text($0.title).tag($0) }
                }
                Picker("Slinky environment", selection: $env) {
                    ForEach(AppEnvironment.allCases) { Text($0.title).tag($0) }
                }
                if let label = host.targetLabel {
                    TextField(label, text: $target, prompt: Text(host == .fly ? "from fly.toml" : "my-site"))
                }
                if host == .vercel {
                    LabeledContent("Vercel environment", value: HostPush.vercelTarget(env.rawValue).capitalized)
                }
                if host == .netlify {
                    Text("Netlify gets them for every deploy context.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: host.targetLabel != nil || host == .vercel || host == .netlify ? 168 : 128)

            if folder == nil {
                Label("Link the project folder first (Add › Link Folder…): the host's tool reads its settings from there.", systemImage: "folder.badge.questionmark")
                    .foregroundStyle(Color.attention).font(.callout)
            } else if names.isEmpty {
                Text("No variables have a \(env.title) value.").foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("\(chosen.count) of \(names.count) will be sent").font(.headline)
                    Spacer()
                    if host.canCompare {
                        Button("Compare with \(host.title)") { compare() }.disabled(working).controlSize(.small)
                    }
                }
                List(names, id: \.self) { name in
                    HStack {
                        Toggle(isOn: Binding(get: { chosen.contains(name) }, set: { on in if on { chosen.insert(name) } else { chosen.remove(name) } })) {
                            Text(name).font(.system(.body, design: .monospaced))
                        }
                        Spacer()
                        if let remote {
                            Text(remote.contains(name) ? "replaces the host's" : "new on the host")
                                .font(.caption).foregroundStyle(remote.contains(name) ? Color.attention : Color.secondary)
                        }
                    }
                }
                .frame(minHeight: 140)
                if let remote {
                    let extra = remote.subtracting(names).sorted()
                    if !extra.isEmpty {
                        Text("Only on \(host.title): \(extra.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if let message { Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }

            HStack {
                if working { ProgressView().controlSize(.small) }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Send \(chosen.count)…") { send() }
                    .keyboardShortcut(.defaultAction)
                    .glassProminentButton()
                    .disabled(working || chosen.isEmpty || folder == nil || (host.targetLabel != nil && target.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
        .padding(22)
        .frame(width: 520, height: 600)
        .onAppear(perform: reset)
        .onChange(of: env) { reset() }
        .onChange(of: host) { remote = nil; if host == .fly, target.isEmpty, let f = folder { target = HostPush.flyApp(in: f) ?? "" } }
    }

    private func reset() {
        chosen = Set((project?.variables ?? []).filter { $0.value(in: env) != nil }.map(\.name))
        remote = nil
        message = nil
    }

    private func compare() {
        guard let folder else { return }
        working = true
        let host = host, env = env.rawValue, target = target
        Task {
            let names = await Task.detached { HostPush.remoteNames(host, environment: env, folder: folder, target: target) }.value
            working = false
            remote = names
            if names == nil { message = "Couldn't read the list from \(host.title). Is \(host.tool) installed and signed in?" }
        }
    }

    private func send() {
        guard let project, let folder else { return }
        let values = Dictionary(uniqueKeysWithValues: project.variables.compactMap { v in
            chosen.contains(v.name) ? v.value(in: env).map { (v.name, $0) } : nil
        })
        working = true
        let host = host, envName = env.rawValue, target = target.trimmingCharacters(in: .whitespaces)
        Task {
            guard await model.approve(reason: "send \(counted(values.count, "variable")) from \(project.name) (\(env.title)) to \(host.title)") else {
                working = false
                return
            }
            let result = await Task.detached { HostPush.send(host, values: values, environment: envName, folder: folder, target: target) }.value
            working = false
            if !result.sent.isEmpty {
                model.record(ActivityEntry(action: .pushed, names: result.sent, detail: "\(project.name) (\(env.title)) to \(host.title)"))
            }
            if result.failed.isEmpty {
                message = "Sent \(result.sent.count) to \(host.title)."
                model.show("Sent \(counted(result.sent.count, "variable")) to \(host.title).")
            } else {
                message = "Sent \(result.sent.count). Didn't send: " + result.failed.map { k, v in k == "*" ? v : "\(k) (\(v.split(separator: "\n").last ?? ""))" }.joined(separator: "; ")
            }
        }
    }
}
