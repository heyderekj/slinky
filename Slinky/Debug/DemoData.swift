#if DEBUG
import Foundation
import SlinkyCoreShared

/// Debug builds only: fake vaults for looking at the app with kind data, worst-case data, nothing, one of
/// everything, or a lot. Start with `--demo-data worst` (or demo, empty, one, thousand), or use the Demo menu.
/// Every value is obviously fake (it contains EXAMPLE). Nothing here is ever saved: `persist()` returns early in demo
/// mode, and demo mode never opens the real vault, the socket, the clipboard watcher, reminders or the update check.
enum DemoFixture: String, CaseIterable, Identifiable {
    case demo, worst, empty, one, thousand
    var id: String { rawValue }

    var title: String {
        switch self {
        case .demo: "Demo Data"
        case .worst: "Worst Case"
        case .empty: "Empty"
        case .one: "One of Everything"
        case .thousand: "1,000 Items"
        }
    }

    /// `--demo-data <state>` from the launch arguments.
    static var fromArguments: DemoFixture? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--demo-data") else { return nil }
        return i + 1 < args.count ? DemoFixture(rawValue: args[i + 1]) ?? .worst : .worst
    }

    func document(now: Date = .now) -> VaultDocument {
        switch self {
        case .empty: VaultDocument()
        case .demo: Self.demoDocument(now)
        case .worst: Self.worstDocument(now)
        case .one: Self.oneDocument(now)
        case .thousand: Self.thousandDocument(now)
        }
    }

    /// Findings for Health, so it never scans the disk in demo mode.
    func leaks() -> [LeakFinding] {
        switch self {
        case .worst:
            return [
                LeakFinding(place: .envFile(path: NSHomeDirectory() + "/Developer/clients/northwind-industries-holdings/web/apps/storefront/.env.production.local", projectID: nil),
                            names: ["STRIPE_SECRET_KEY_PRODUCTION_EU_WEST", "DATABASE_URL", "RESEND_API_KEY"]),
                LeakFinding(place: .transcript(tool: "Claude Code", path: NSHomeDirectory() + "/.claude/projects/-Users-aleksandra-Developer-clients-northwind-industries-holdings-web/9f8e7d6c-5b4a-4c3d-8e2f-1a0b9c8d7e6f.jsonl"),
                            names: ["OPENAI_API_KEY"]),
                LeakFinding(place: .commit(repo: NSHomeDirectory() + "/Developer/harbor-app", hash: "a1b2c3d", project: "harbor-app"),
                            names: ["GITHUB_TOKEN", "SENTRY_AUTH_TOKEN"]),
                LeakFinding(place: .history(path: NSHomeDirectory() + "/.zsh_history"), names: ["CLOUDFLARE_API_TOKEN"]),
            ]
        case .one:
            return [LeakFinding(place: .history(path: NSHomeDirectory() + "/.zsh_history"), names: ["GITHUB_TOKEN"])]
        default:
            return []
        }
    }

    // MARK: Builders

    private static func day(_ n: Double, from now: Date) -> Date { now.addingTimeInterval(n * 86_400) }

    private static func codes(_ n: Int) -> [String] {
        (0..<n).map { i in String(format: "ex%03d-mpl%02d", i, i % 97) }
    }

    private static func demoDocument(_ now: Date) -> VaultDocument {
        var doc = VaultDocument()
        doc.keys = [
            Key(name: "CLOUDFLARE_API_TOKEN", value: "EXAMPLE00000000000000Q7vX", note: nil, link: "https://dash.cloudflare.com/profile/api-tokens"),
            Key(name: "STRIPE_SECRET_KEY", value: "sk_live_EXAMPLE0000004f2a", provider: "Stripe", isLive: true),
            Key(name: "GITHUB_TOKEN", value: "ghp_EXAMPLE00000000008c1d", provider: "GitHub", expires: day(5, from: now)),
            Key(name: "OPENAI_API_KEY", value: "sk-proj-EXAMPLE00000Tx4c", provider: "OpenAI"),
        ]
        doc.keys[0].service = "cloudflare"
        var gh = CodeSet(account: "GitHub", username: "@harbor", codes: codes(10))
        gh.used = [0, 1]
        doc.codeSets = [gh]
        doc.kept = [KeptItem(label: "Apple Account recovery key", kind: .recoveryKey, from: "Apple", value: "R7KQ-EXAM-PLE0-0000")]
        doc.kept[0].printedCopy = true
        doc.projects = [Project(name: "harbor-app", variables: [
            Variable(name: "DATABASE_URL", values: [.local: "postgres://EXAMPLE@localhost/harbor", .production: "postgres://EXAMPLE@db/harbor"]),
            Variable(name: "STRIPE_SECRET_KEY", values: [.local: "sk_test_EXAMPLE", .production: "sk_live_EXAMPLE0000004f2a"], provider: "Stripe"),
            Variable(name: "NEXT_PUBLIC_STRIPE_KEY", values: [.local: "pk_test_EXAMPLE"], isPlain: true, provider: "Stripe"),
        ], expected: ["DATABASE_URL", "STRIPE_SECRET_KEY", "NEXT_PUBLIC_STRIPE_KEY", "POSTHOG_KEY", "SENTRY_DSN"])]
        doc.log = [ActivityEntry(action: .copied, names: ["STRIPE_SECRET_KEY"], date: now.addingTimeInterval(-3600)),
                   ActivityEntry(action: .ran, names: ["DATABASE_URL", "STRIPE_SECRET_KEY"], actor: "Claude Code", detail: "npm run dev in harbor-app", date: now.addingTimeInterval(-7200))]
        return doc
    }

    private static func worstDocument(_ now: Date) -> VaultDocument {
        var doc = VaultDocument()
        let longNote = String(repeating: "Rotated after the March incident; ask Bartholomew before changing scopes. Used by the nightly export job, the staging preview deploys and two contractors' laptops. ", count: 12)
        doc.keys = [
            // Names that only differ at the end, so tail truncation makes them look the same.
            Key(name: "STRIPE_SECRET_KEY_PRODUCTION_EU_WEST", value: "sk_live_EXAMPLE4f2aEU", provider: "Stripe", isLive: true, expires: day(-3, from: now)),
            Key(name: "STRIPE_SECRET_KEY_PRODUCTION_US_EAST", value: "sk_live_EXAMPLE4f2aUS", provider: "Stripe", isLive: true, expires: day(0.2, from: now)),
            Key(name: "CLOUDFLARE_API_TOKEN", value: "EXAMPLE00000000000000Q7vX", note: longNote,
                link: "https://dash.cloudflare.com/9f8e7d6c5b4a4c3d8e2f1a0b9c8d7e6f/workers-and-pages/view/northwind-storefront/settings/variables?environment=production"),
            Key(name: "GH", value: "ghp_EXAMPLE00000000008c1d", provider: "GitHub", expires: day(1, from: now)),
            // Short values: Peek must not give them away.
            Key(name: "SHORT_TOKEN", value: "sk_live_xyz", isLive: true),
            Key(name: "PIN", value: "EX42"),
            Key(name: "BARTHOLOMEW_FITZGERALD_NORTHWIND_INDUSTRIES_HOLDINGS_INTERNAL_BILLING_WEBHOOK_SIGNING_SECRET", value: "whsec_EXAMPLE0000000000000000000000000000"),
            Key(name: "Benachrichtigungseinstellungen", value: "EXAMPLE-ohne-Leerzeichen-0000000000"),
        ]
        doc.keys[2].service = "cloudflare"
        doc.keys[0].created = day(-400, from: now)
        var none = CodeSet(account: "Aleksandra Wiśniewska-Kowalczyk", username: "bartholomew.fitzgerald@northwind-industries-holdings.example.com", codes: codes(10))
        none.used = Set(0..<10)
        var one = CodeSet(account: "Jo", username: "a@b.co", codes: codes(16))
        one.used = Set(0..<15)
        let cjk = CodeSet(account: "王秀英", codes: codes(8))
        let rtl = CodeSet(account: "نور الهدى عبد الرحمن", codes: codes(12))
        let emoji = CodeSet(account: "👩🏽‍💻 Priya", codes: ["ex-long-recovery-code-0000-EXAMPLE-aaaa", "ex-long-recovery-code-0001-EXAMPLE-bbbb", "ex-long-recovery-code-0002-EXAMPLE-cccc", "ex-long-recovery-code-0003-EXAMPLE-dddd"])
        doc.codeSets = [none, one, cjk, rtl, emoji]
        doc.kept = [
            KeptItem(label: "Christopher Alexander Montgomery III — Apple Account recovery key", kind: .recoveryKey, from: "Apple", value: "R7KQ-EXAM-PLE0-0000-0000-0000-0000"),
            KeptItem(label: "J", kind: .setupKey, from: "ops@sub.department.region.example.co.uk", value: "EXAMPLEEXAMPLEEXAMPLE"),
        ]
        doc.projects = [
            Project(name: "northwind-industries-holdings-storefront-monorepo", folders: [NSHomeDirectory() + "/Developer/clients/northwind-industries-holdings/web/apps/storefront", NSHomeDirectory() + "/Developer/x"],
                    variables: (0..<40).map { i in
                        Variable(name: i == 0 ? "NEXT_PUBLIC_SUPABASE_ANON_KEY_FOR_THE_STOREFRONT_PREVIEW_DEPLOYMENTS" : "SERVICE_\(i)_API_KEY",
                                 values: [.local: "EXAMPLE-local-\(i)", .preview: "EXAMPLE-preview-\(i)", .production: "EXAMPLE-production-\(i)"],
                                 isPlain: i % 7 == 0)
                    },
                    expected: ["SERVICE_1_API_KEY", "POSTHOG_KEY", "POSTHOG_KEY", "SENTRY_DSN", "A_VERY_LONG_EXPECTED_VARIABLE_NAME_FROM_DOT_ENV_EXAMPLE_THAT_IS_MISSING", "RESEND_API_KEY", "UPSTASH_REDIS_REST_TOKEN"]),
            Project(name: "Jo", variables: [Variable(name: "X", values: [.local: "EXAMPLE"])]),
            Project(name: "new-site"),   // empty, for the empty project screen
        ]
        var files: [SecretFile] = []
        var asc = SecretFile(name: "App Store Connect API key for Northwind Industries Holdings (Team B3U6EXAMPLE)",
                             filename: "AuthKey_EXAMPLE1234_Q3-board-deck-FINAL-revised-v12-approved-by-legal.p8",
                             kind: .appStoreConnectKey, data: Data("EXAMPLE".utf8),
                             fields: ["Issuer ID": "69a6de70-EXAM-PLE0-0000-000000000000", "Key ID": "EXAMPLE123"])
        asc.note = "Ask Jo."
        files.append(asc)
        files.append(SecretFile(name: "x", filename: "IMG_20250914_183022_HDR_portrait_edited_edited.json", kind: .serviceAccount, data: Data("{}".utf8)))
        doc.secretFiles = files
        let actors = ["You", "Claude Code", "Terminal", "Xcode", "Cursor"]
        let actions: [ActivityEntry.Action] = [.copied, .ran, .codeUsed, .requested, .leakFound]
        let many = ["STRIPE_SECRET_KEY_PRODUCTION_EU_WEST", "DATABASE_URL", "RESEND_API_KEY", "OPENAI_API_KEY", "SENTRY_DSN"]
        let longDetail = "npm run dev in northwind-industries-holdings-storefront-monorepo (Also updated in harbor-app, Portfolio, Slinky and 3 more)"
        var log: [ActivityEntry] = []
        for i in 0..<1000 {
            let names: [String] = i % 9 == 0 ? many : ["GITHUB_TOKEN"]
            let detail: String = i % 4 == 0 ? longDetail : ""
            let date = now.addingTimeInterval(-Double(i) * 3700)
            log.append(ActivityEntry(action: actions[i % 5], names: names, actor: actors[i % actors.count], detail: detail, date: date))
        }
        doc.log = log
        doc.trashed = [TrashEntry(.key(Key(name: "STRIPE_SECRET_KEY_PRODUCTION_EU_WEST_OLD_ROTATED_2026_03", value: "sk_live_EXAMPLEold")), deletedAt: day(-29.5, from: now)),
                       TrashEntry(.codes(CodeSet(account: "Konstantin Oberhauser-Wettstein", codes: codes(10))), deletedAt: day(-1, from: now))]
        return doc
    }

    private static func oneDocument(_ now: Date) -> VaultDocument {
        var doc = VaultDocument()
        doc.keys = [Key(name: "GITHUB_TOKEN", value: "ghp_EXAMPLE00000000008c1d", provider: "GitHub", isLive: true, expires: day(1, from: now))]
        doc.keys[0].created = day(-90, from: now)
        var set = CodeSet(account: "GitHub", codes: codes(2))
        set.used = [0]
        doc.codeSets = [set]
        doc.kept = [KeptItem(label: "Apple Account recovery key", kind: .recoveryKey, value: "R7KQ-EXAM-PLE0-0000")]
        doc.projects = [Project(name: "harbor-app", variables: [Variable(name: "DATABASE_URL", values: [.local: "postgres://EXAMPLE@localhost/harbor"])],
                                expected: ["DATABASE_URL", "SENTRY_DSN"])]
        doc.secretFiles = [SecretFile(name: "App Store Connect API key", filename: "AuthKey_EXAMPLE.p8", kind: .appStoreConnectKey, data: Data("EXAMPLE".utf8))]
        doc.log = [ActivityEntry(action: .copied, names: ["GITHUB_TOKEN"], date: now.addingTimeInterval(-60))]
        doc.trashed = [TrashEntry(.key(Key(name: "OLD_TOKEN", value: "EXAMPLE")), deletedAt: day(-1, from: now))]
        return doc
    }

    private static func thousandDocument(_ now: Date) -> VaultDocument {
        var doc = VaultDocument()
        let services = ["Stripe", "GitHub", "OpenAI", "Cloudflare", "Vercel", "Supabase", "Resend", "AWS"]
        doc.keys = (0..<1000).map { i in
            Key(name: "SERVICE_\(i)_API_KEY", value: "EXAMPLE-\(i)-0000000000000", provider: services[i % services.count],
                isLive: i % 11 == 0, expires: i % 13 == 0 ? day(Double(i % 40), from: now) : nil)
        }
        doc.codeSets = (0..<60).map { i in CodeSet(account: "Account \(i)", codes: codes(10)) }
        doc.projects = (0..<25).map { p in
            Project(name: "project-\(p)", variables: (0..<40).map { i in Variable(name: "VAR_\(i)", values: [.local: "EXAMPLE-\(i)"]) })
        }
        doc.log = (0..<1000).map { i in ActivityEntry(action: .copied, names: ["SERVICE_\(i)_API_KEY"], date: now.addingTimeInterval(-Double(i) * 600)) }
        return doc
    }
}
#endif
