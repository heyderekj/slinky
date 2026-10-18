import AppKit
import SlinkyCoreShared

/// What the `slinky` command may ask for, and the rules. Values leave only for an approved `env` request,
/// and only to the CLI (the app's own signed binary, checked by BrokerServer). Everything else is names only,
/// and names only while unlocked.
extension AppModel {
    func handle(_ request: Broker.Request, peer: Peer) async -> Broker.Response {
        switch request.op {
        case .status:
            var r = Broker.Response(ok: true)
            r.unlocked = isUnlocked
            r.message = !hasVault ? "Slinky has no vault yet." : isUnlocked ? "Unlocked." : "Locked."
            return r
        case .list: return listNames()
        case .projectForDir: return projectForDir(request.cwd)
        case .env: return await environment(request, peer: peer)
        case .check: return check(request)
        case .request: return requestSecret(request, peer: peer)
        case .guardDiff: return await guardDiff(request, peer: peer)
        case .notarize: return await notarizeProfile(request, peer: peer)
        }
    }

    // MARK: Names

    private func listNames() -> Broker.Response {
        guard isUnlocked else { return .fail("Slinky is locked. Unlock it to see names.") }
        var r = Broker.Response(ok: true)
        var lines: [String] = []
        for key in document.keys {
            lines.append("key\t\(key.name)\t\(key.provider ?? "")\t\(key.isLive ? "live" : "")\t\(agentUsable(key) ? "agents" : "not for agents")")
        }
        for project in document.projects {
            for v in project.variables {
                let envs = AppEnvironment.allCases.filter { v.value(in: $0) != nil }.map(\.title).joined(separator: ",")
                lines.append("var\t\(project.name)/\(v.name)\t\(envs)\t\(v.isPlain ? "plain" : "secret")\t\(v.agentPolicy == .neverLeaves ? "not for agents" : "agents")")
            }
        }
        for file in document.secretFiles { lines.append("file\t\(file.name)\t\(file.kind.title)") }
        r.lines = lines
        return r
    }

    private func project(for cwd: String) -> Project? {
        document.projects.first { Broker.path(cwd, isInside: $0.folders) }
    }

    private func projectForDir(_ cwd: String) -> Broker.Response {
        guard isUnlocked, let p = project(for: cwd) else { return .fail("") }
        var r = Broker.Response(ok: true)
        r.project = p.name
        return r
    }

    private func check(_ request: Broker.Request) -> Broker.Response {
        guard isUnlocked else { return .fail("Slinky is locked.") }
        let folder = request.text ?? request.cwd
        guard let p = project(for: folder) ?? document.projects.first(where: { $0.name.caseInsensitiveCompare(request.project ?? "") == .orderedSame }) else {
            // Not a linked project: read its .env.example for the names it expects, and say which Slinky has nowhere.
            let scan = ProjectScan.scan(URL(fileURLWithPath: folder))
            guard let example = scan.exampleFile,
                  let text = try? String(contentsOf: URL(fileURLWithPath: folder).appendingPathComponent(example), encoding: .utf8) else {
                return .fail("This folder isn't a Slinky project, and has no .env.example.")
            }
            let have = Set(document.projects.flatMap { $0.variables.map(\.name) } + document.keys.map(\.name))
            var r = Broker.Response(ok: true)
            r.names = DotEnv.names(text).filter { !have.contains($0) }
            r.message = "Not linked to a Slinky project yet."
            return r
        }
        var r = Broker.Response(ok: true)
        r.project = p.name
        r.names = p.missing
        return r
    }

    // MARK: Values, with approval

    private func agentUsable(_ key: Key) -> Bool { key.agentPolicy != .neverLeaves && !key.isLive }

    private func environment(_ request: Broker.Request, peer: Peer) async -> Broker.Response {
        guard hasVault else { return .fail("Slinky has no vault yet. Save something in Slinky first.") }
        let purpose = request.purpose ?? .run
        if peer.isAgent {
            guard purpose == .run else { return .fail("Agents can only use secrets through `slinky run -- <command>`.") }
            if let refusal = Broker.agentRefusal(request.argv) { return .fail(refusal) }
        }
        // Make sure we can see the vault before resolving names (the unlock is also the approval).
        let what = describe(request, peer: peer)
        if !isUnlocked {
            guard await unlockForRequest(reason: what) else { return .fail("Not allowed.") }
        }
        let env = AppEnvironment(rawValue: (request.environment ?? "local").lowercased()) ?? .local
        let proj = request.project.flatMap { name in document.projects.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } }
            ?? (request.keys.isEmpty || request.project != nil ? project(for: request.cwd) : nil)
        if request.project != nil, proj == nil { return .fail("No Slinky project called \(request.project!).") }
        var values: [String: String] = [:]
        var withheld: [String] = []
        var missing: [String] = []
        if let proj {
            for v in proj.variables {
                guard let value = v.value(in: env) else { continue }
                if peer.isAgent, v.agentPolicy == .neverLeaves || (!v.isPlain && Detector.detect(value)?.isLive == true) {
                    withheld.append(v.name); continue
                }
                values[v.name] = value
            }
            missing = proj.expected.filter { values[$0] == nil && !withheld.contains($0) }
        }
        for name in request.keys {
            guard let key = document.keys.first(where: { $0.name == name }) else { missing.append(name); continue }
            if peer.isAgent, !agentUsable(key) { withheld.append(name); continue }
            values[name] = key.value
        }
        var files: [String: [String]] = [:]
        if purpose == .run {
            for spec in request.files ?? [] {
                let (name, variable) = Broker.fileVariable(spec)
                guard let file = document.secretFiles.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { missing.append(name); continue }
                if peer.isAgent { withheld.append(file.name); continue }
                files[variable] = [file.filename, file.data.base64EncodedString()]
            }
        }
        guard proj != nil || !request.keys.isEmpty || !(request.files ?? []).isEmpty else {
            return .fail("This folder isn't linked to a Slinky project. Link it in Slinky, or pass --project NAME or --key NAME.")
        }
        guard !values.isEmpty || !files.isEmpty else {
            var r = Broker.Response.fail("Nothing to hand over for \(env.title).")
            r.withheld = withheld; r.names = missing
            return r
        }
        // Approval: Touch ID with the exact request, unless the person approved the same thing in the last hour.
        let grantKey = [purpose.rawValue, proj?.id.uuidString ?? "", env.rawValue, request.keys.joined(separator: ","),
                        request.argv.joined(separator: " "), peer.display].joined(separator: "|")
        let reused = !peer.isAgent && (grants[grantKey].map { $0 > .now } ?? false)
        if !reused, !(await approve(reason: describe(request, peer: peer, count: values.count + files.count, project: proj?.name, env: env))) {
            return .fail("Not allowed.")
        }
        if !peer.isAgent { grants[grantKey] = .now.addingTimeInterval(3600) }
        let action: ActivityEntry.Action = purpose == .run ? .ran : purpose == .export ? .exported : .xcconfig
        record(ActivityEntry(action: action, names: values.keys.sorted() + files.values.map { $0[0] }, actor: peer.display,
                             detail: [request.argv.first.map { ($0 as NSString).lastPathComponent }, proj?.name, env.title]
                                .compactMap { $0 }.joined(separator: " · ")))
        var r = Broker.Response(ok: true)
        r.env = values
        r.files = files.isEmpty ? nil : files
        r.withheld = withheld.isEmpty ? nil : withheld
        r.names = missing.isEmpty ? nil : missing
        r.project = proj?.name
        return r
    }

    /// The Touch ID line: who wants what, for which command. Names and counts, never values.
    private func describe(_ request: Broker.Request, peer: Peer, count: Int? = nil, project: String? = nil, env: AppEnvironment? = nil) -> String {
        let who = peer.display == "You" ? "the slinky command" : peer.display
        let things = count.map { "\($0) \($0 == 1 ? "secret" : "secrets")" } ?? "secrets"
        let from = [project, env?.title].compactMap { $0 }.joined(separator: ", ")
        let source = from.isEmpty ? "" : " from \(from)"
        switch request.purpose ?? .run {
        case .run:
            let command = request.argv.prefix(4).joined(separator: " ")
            return "let \(who) run “\(command)” with \(things)\(source)"
        case .export: return "load \(things)\(source) into \(who == "the slinky command" ? "your shell" : who)"
        case .xcconfig: return "give \(who) \(things)\(source) for a build"
        }
    }

    // MARK: Requests from agents

    /// An agent needs a secret Slinky doesn't have: open Add Item with the name filled in, so the person pastes
    /// the value into Slinky, not into the chat. Answers only "prompted".
    private func requestSecret(_ request: Broker.Request, peer: Peer) -> Broker.Response {
        guard let name = request.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
              name.range(of: #"^[A-Za-z_][A-Za-z0-9_]{0,127}$"#, options: .regularExpression) != nil else {
            return .fail("Give a variable name like RESEND_API_KEY.")
        }
        guard isUnlocked else { return .fail("Slinky is locked. Ask the person to unlock it, then try again.") }
        var draft = AddItemPanel.Draft()
        draft.name = name
        draft.nameTouched = true
        if let p = project(for: request.cwd) { draft.project = .existing(p.id); draft.destination = .project; draft.destinationTouched = true }
        if let reason = request.reason?.prefix(200), !reason.isEmpty { draft.note = "Asked for by \(peer.display): \(reason)" }
        addDraft = draft
        tuckPrefill = ""
        openMainWindow?()
        showTuck = true
        show("\(peer.display) needs \(name). Paste it here, not in the chat.", style: .info)
        record(ActivityEntry(action: .requested, names: [name], actor: peer.display))
        var r = Broker.Response(ok: true)
        r.message = "prompted"
        return r
    }

    // MARK: Commit guard

    /// Looks for any saved value in a staged diff. Answers with names only.
    private func guardDiff(_ request: Broker.Request, peer: Peer) async -> Broker.Response {
        guard hasVault else { return Broker.Response(ok: true) }
        if !isUnlocked {
            guard await unlockForRequest(reason: "check this commit for secrets saved in Slinky") else {
                return .fail("Slinky is locked, so this commit wasn't checked.")
            }
        }
        let found = LeakScanner.matches(in: request.text ?? "", secrets: scanSecrets())
        var r = Broker.Response(ok: true)
        r.names = found.isEmpty ? nil : found
        if !found.isEmpty {
            record(ActivityEntry(action: .guarded, names: found, actor: peer.display, detail: "Blocked a commit"))
        }
        return r
    }

    /// Every saved value long enough to search for, with a name to report it by.
    func scanSecrets() -> [LeakScanner.Secret] {
        var out: [LeakScanner.Secret] = []
        for key in document.keys { out.append(.init(name: key.name, value: key.value)) }
        for item in document.kept { out.append(.init(name: item.label, value: item.value)) }
        for p in document.projects {
            for v in p.variables where !v.isPlain {
                for env in AppEnvironment.allCases {
                    if let value = v.value(in: env) { out.append(.init(name: "\(p.name)/\(v.name)", value: value)) }
                }
            }
        }
        return out
    }
}
