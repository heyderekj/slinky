import Foundation
import SlinkyCoreShared
@testable import SlinkyCoreVault
import Testing

// Every value in these tests is fake.

@Suite("Detection")
struct DetectionTests {
    /// Derek's day (2026-10-16): a recovery key, a personal API token and an env secret.
    @Test("Derek's three items each go to the right place")
    func dereksDay() throws {
        let recovery = try #require(Detector.detect("R7KQ-2MXP-9TDV-4HCE-W8NA-3FJB-6YLZ"))
        #expect(recovery.kind == .recoveryKey)
        #expect(recovery.destination == .kept)
        #expect(recovery.label == "Looks like an Apple recovery key.")

        let token = try #require(Detector.detect("github_pat_11EXAMPLE0000aaaaBBBBccccDDDDeeee"))
        #expect(token.destination == .key)
        #expect(token.suggestedName == "GITHUB_TOKEN")

        let env = try #require(Detector.detect("RESEND_API_KEY=re_EXAMPLE_8KcPq2Lm"))
        #expect(env.destination == .project)
        #expect(env.suggestedName == "RESEND_API_KEY")
    }

    @Test func stripeLiveAndTest() throws {
        let live = try #require(Detector.detect("sk_live_EXAMPLE9Zx7Lm2Qp4f2a"))
        #expect(live.isLive)
        #expect(live.label == "Looks like a Stripe live key.")
        let test = try #require(Detector.detect("sk_test_EXAMPLE4Rt6Yh1Wq81cd"))
        #expect(!test.isLive)
        let publishable = try #require(Detector.detect("pk_live_EXAMPLE123456"))
        #expect(publishable.kind == .plainConfig)
    }

    @Test func recoveryCodeBlock() throws {
        let block = """
        Your GitHub recovery codes
        a1b2c-3d4e5
        f6a7b-8c9d0
        e1f2a-3b4c5
        d6e7f-8a9b0
        Keep them somewhere safe.
        """
        let d = try #require(Detector.detect(block))
        guard case let .recoveryCodes(codes) = d.kind else { Issue.record("expected codes"); return }
        #expect(codes.count == 4)
        #expect(d.provider == "GitHub")
        #expect(d.destination == .codes)
    }

    @Test func walletSeedIsRefused() throws {
        let seed = "apple banana cherry delta eagle fable gamma hotel india juliet kilo lemon"
        #expect(try #require(Detector.detect(seed)).kind == .walletSeed)
    }

    @Test func setupKeyAndUnknown() throws {
        #expect(try #require(Detector.detect("otpauth://totp/GitHub:derek?secret=EXAMPLE")).kind == .setupKey)
        #expect(try #require(Detector.detect("hunter2-correct-horse")).kind == .unknown)
    }

    @Test func peek() {
        #expect(Peek.of("sk_live_EXAMPLE9Zx7Lm2Qp4f2a") == "sk_live_…4f2a")
        #expect(Peek.of("short") == "••••••••")
    }
}

@Suite("DotEnv")
struct DotEnvTests {
    @Test func parsesTheUsualMess() {
        let text = """
        # Payments
        STRIPE_SECRET_KEY=sk_test_EXAMPLE
        export STRIPE_WEBHOOK_SECRET="whsec_EXAMPLE"   # webhook
        # Public
        NEXT_PUBLIC_SUPABASE_URL='https://example.supabase.co'
        NOT A LINE
        EMPTY=
        """
        let lines = DotEnv.parse(text)
        #expect(lines.map(\.name) == ["STRIPE_SECRET_KEY", "STRIPE_WEBHOOK_SECRET", "NEXT_PUBLIC_SUPABASE_URL", "EMPTY"])
        #expect(lines[1].value == "whsec_EXAMPLE")
        #expect(lines[1].group == "Payments")
        #expect(lines[2].isPlain)
        #expect(lines[2].value == "https://example.supabase.co")
        #expect(lines[3].value == "")
    }

    @Test func missingFromExample() {
        var project = Project(name: "harvous", expected: DotEnv.names("RESEND_API_KEY=\nSTRIPE_SECRET_KEY="))
        project.variables = [Variable(name: "STRIPE_SECRET_KEY", values: [.local: "sk_test_EXAMPLE"])]
        #expect(project.missing == ["RESEND_API_KEY"])
    }
}

@Suite("Vault")
struct VaultTests {
    func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("slinky-test-\(UUID().uuidString)/vault.slinky")
    }

    @Test func roundTripAndRecovery() throws {
        let url = tempURL()
        let store = VaultStore(url: url, enclave: SoftwareWrapper())
        var (session, recovery) = try store.create()
        session.document.kept.append(KeptItem(label: "Apple ID recovery key", kind: .recoveryKey, value: "R7KQ-EXAMPLE"))
        try store.save(session)

        let reopened = try store.unlock(context: nil)
        #expect(reopened.document.kept.first?.value == "R7KQ-EXAMPLE")

        // A different "Mac" (new enclave key) can still get in with the Recovery Key, and gets re-wrapped.
        let newMac = VaultStore(url: url, enclave: SoftwareWrapper())
        let restored = try newMac.unlock(recovery: try #require(RecoveryKey(recovery.display.lowercased())))
        #expect(restored.document == session.document)
        #expect(try newMac.unlock(context: nil).document == session.document)

        // The file never contains the secret in the clear.
        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(!raw.contains("R7KQ-EXAMPLE"))
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }

    @Test func replacingRecoveryKeyRetiresTheOldOne() throws {
        let url = tempURL()
        let store = VaultStore(url: url, enclave: SoftwareWrapper())
        var (session, old) = try store.create()
        session.document.keys.append(Key(name: "GITHUB_TOKEN", value: "ghp_EXAMPLE"))
        try store.save(session)

        let new = try store.replaceRecoveryKey(for: session)
        #expect(new.display != old.display)
        #expect(throws: VaultError.wrongRecoveryKey) { try store.unlock(recovery: old) }
        #expect(try store.unlock(recovery: new).document == session.document)
        // Touch ID on this Mac still works.
        #expect(try store.unlock(context: nil).document == session.document)
    }

    @Test func wrongRecoveryKeyFails() throws {
        let store = VaultStore(url: tempURL(), enclave: SoftwareWrapper())
        _ = try store.create()
        #expect(throws: VaultError.wrongRecoveryKey) { try store.unlock(recovery: RecoveryKey.generate()) }
    }

    @Test func recoveryKeyFormat() throws {
        let key = RecoveryKey.generate()
        #expect(key.display.count == 39) // 8 groups of 4 + 7 dashes
        #expect(RecoveryKey(key.display) == key)
        #expect(RecoveryKey(key.display.replacingOccurrences(of: "-", with: " ")) == key)
        #expect(RecoveryKey("too-short") == nil)
    }
}

@Suite("Project scan")
struct ProjectScanTests {
    private func folder(_ files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("slinky-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, text) in files {
            if name.hasSuffix("/") {
                try FileManager.default.createDirectory(at: dir.appendingPathComponent(name), withIntermediateDirectories: true)
            } else {
                try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }
        }
        return dir
    }

    @Test func findsEnvFilesAndGuessesEnvironments() throws {
        let dir = try folder([
            ".env.local": "A=EXAMPLE\nB=EXAMPLE",
            ".env.production": "A=EXAMPLE",
            ".env.staging": "A=EXAMPLE",
            ".env.example": "A=\nB=\nC=",
            "package.json": "{}",
        ])
        let scan = ProjectScan.scan(dir)
        #expect(scan.envFiles.map(\.fileName) == [".env.local", ".env.staging", ".env.production"])
        #expect(scan.envFiles.map(\.environment) == [.local, .preview, .production])
        #expect(scan.envFiles[0].names == ["A", "B"])
        #expect(scan.exampleFile == ".env.example")
        #expect(scan.expected == ["A", "B", "C"])
        #expect(!scan.isGitRepo)
        #expect(scan.envFiles.allSatisfy { $0.ignoredByGit == nil })
    }

    @Test func checksGitignore() throws {
        let dir = try folder([
            ".git/": "",
            ".gitignore": "node_modules/\n.env*.local\n# comment\n",
            ".env.local": "A=EXAMPLE",
            ".env.production": "A=EXAMPLE",
        ])
        let scan = ProjectScan.scan(dir)
        #expect(scan.isGitRepo)
        #expect(scan.envFiles.first { $0.fileName == ".env.local" }?.ignoredByGit == true)
        #expect(scan.envFiles.first { $0.fileName == ".env.production" }?.ignoredByGit == false)
    }

    @Test func gitignoreNegationAndAnchors() {
        #expect(ProjectScan.isIgnored(".env", by: ["/.env"]))
        #expect(ProjectScan.isIgnored(".env.local", by: [".env*"]))
        #expect(!ProjectScan.isIgnored(".env.local", by: [".env*", "!.env.local"]))
        #expect(ProjectScan.isIgnored(".env.production", by: ["**/.env.*"]))
    }
}

@Suite("Import")
struct ImportTests {
    private let export = """
    {"accounts":[{"attrs":{"name":"Derek"},"vaults":[{"attrs":{"name":"Personal"},"items":[
      {"uuid":"a","categoryUuid":"112","overview":{"title":"OpenAI"},"details":{"sections":[{"fields":[
        {"id":"credential","value":{"concealed":"sk-proj-EXAMPLEEXAMPLEEXAMPLE"}},
        {"id":"expires","value":{"date":1893456000}}]}]}},
      {"uuid":"b","categoryUuid":"001","overview":{"title":"GitHub","url":"https://github.com"},
       "details":{"loginFields":[{"designation":"password","value":"EXAMPLE-password"}],
                  "notesPlain":"Backup codes\\nab12c-3de45\\nfg67h-8ij90\\nkl12m-3no45\\npq67r-8st90"}},
      {"uuid":"c","categoryUuid":"001","overview":{"title":"Netflix"},"details":{"loginFields":[{"designation":"password","value":"EXAMPLE"}]}},
      {"uuid":"d","categoryUuid":"003","overview":{"title":"Stripe"},"details":{"sections":[{"fields":[
        {"id":"x","value":{"concealed":"sk_live_EXAMPLEEXAMPLE"}}]}]}},
      {"uuid":"e","categoryUuid":"003","overview":{"title":"Old"},"state":"archived","details":{"notesPlain":"ABCD-EFGH-JKLM-NPQR-STUV-WXYZ-2345"}}
    ]}]}]}
    """

    @Test func onePasswordFindsKeysAndCodesAndSkipsPasswords() throws {
        let result = try Importer.onePassword(Data(export.utf8))
        #expect(result.candidates.count == 3)
        let openAI = try #require(result.candidates.first { $0.name == "OpenAI" })
        if case let .key(provider, _, expires) = openAI.kind {
            #expect(provider == "OpenAI")
            #expect(expires != nil)
        } else { Issue.record("OpenAI should be a key") }
        let github = try #require(result.candidates.first { $0.name == "GitHub" })
        if case let .codes(codes) = github.kind { #expect(codes.count == 4) } else { Issue.record("GitHub should be codes") }
        let stripe = try #require(result.candidates.first { $0.value.hasPrefix("sk_live_") })
        #expect(stripe.name == "STRIPE_SECRET_KEY")
        #expect(!result.candidates.contains { $0.value.contains("password") })
        #expect(result.skippedPasswords == 1)   // Netflix
    }

    @Test func readsAOnePuxZip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("slinky-1pux-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(export.utf8).write(to: dir.appendingPathComponent("export.data"))
        let zip = dir.appendingPathComponent("test.1pux")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.currentDirectoryURL = dir
        p.arguments = ["-q", zip.path, "export.data"]
        try p.run(); p.waitUntilExit()
        let result = try Importer.read(zip)
        #expect(result.candidates.count == 3)
    }

    @Test func csvFromAPasswordManagerKeepsOnlyKeysAndCodes() {
        let text = """
        Title,URL,Username,Password,Notes,OTPAuth
        GitHub,https://github.com,derek,EXAMPLE-password,"Codes:
        ab12c-3de45
        fg67h-8ij90
        kl12m-3no45
        pq67r-8st90",
        Anthropic,https://console.anthropic.com,derek,sk-ant-EXAMPLEEXAMPLE,,
        Bank,https://bank.example,derek,EXAMPLE,,
        """
        let result = Importer.csv(text, source: "Passwords")
        #expect(result.candidates.count == 2)
        #expect(result.candidates.contains { if case .codes = $0.kind { return $0.name == "GitHub" }; return false })
        #expect(result.candidates.contains { $0.name == "ANTHROPIC_API_KEY" })
        #expect(result.skippedPasswords == 1)
    }

    @Test func plainNameValueSheet() {
        let result = Importer.csv("name,value\nMY_SERVICE_TOKEN,EXAMPLE123\n\"Quoted, name\",\"has \"\"quotes\"\"\"\n", source: "keys")
        #expect(result.candidates.map(\.name) == ["MY_SERVICE_TOKEN", "Quoted, name"])
        #expect(result.candidates.last?.value == "has \"quotes\"")
    }
}

@Suite("Document format")
struct DocumentFormatTests {
    /// A vault written by 1.0: none of the 1.1 fields (links, icons, Recently Deleted, website icons).
    static let v1JSON = """
    {"codeSets":[{"account":"GitHub","codes":["aaaa-bbbb","cccc-dddd"],"created":800000000,"id":"7B1B3C2E-0000-4000-8000-000000000001","used":[]}],
     "formatVersion":1,
     "keys":[{"agentPolicy":"agentsCanUse","created":800000000,"id":"7B1B3C2E-0000-4000-8000-000000000002","isLive":false,"name":"GITHUB_TOKEN","updated":800000000,"value":"ghp_EXAMPLE"}],
     "kept":[{"created":800000000,"id":"7B1B3C2E-0000-4000-8000-000000000003","kind":"recoveryKey","label":"Apple Account","printedCopy":true,"value":"EXAMPLE-KEY"}],
     "projects":[{"created":800000000,"expected":[],"folders":[],"id":"7B1B3C2E-0000-4000-8000-000000000004","name":"harbor","variables":[{"agentPolicy":"agentsCanUse","created":800000000,"id":"7B1B3C2E-0000-4000-8000-000000000005","isPlain":false,"name":"API_KEY","updated":800000000,"values":{"local":"EXAMPLE"}}]}]}
    """

    @Test("A 1.0 vault opens in 1.1")
    func opensAVersionOneDocument() throws {
        let doc = try JSONDecoder().decode(VaultDocument.self, from: Data(Self.v1JSON.utf8))
        #expect(doc.keys.first?.name == "GITHUB_TOKEN")
        #expect(doc.keys.first?.link == nil)
        #expect(doc.codeSets.first?.note == nil)
        #expect(doc.kept.first?.icon == nil)
        #expect(doc.trashed.isEmpty)
        #expect(doc.siteIcons == nil)
    }

    @Test("Links, notes, icons and Recently Deleted survive a round trip")
    func newFieldsRoundTrip() throws {
        var doc = VaultDocument()
        var key = Key(name: "CLOUDFLARE_TOKEN", value: "EXAMPLE", note: "Workers deploys", link: "https://dash.cloudflare.com")
        key.icon = .service("cloudflare")
        doc.keys = [key]
        doc.trashed = [TrashEntry(.kept(KeptItem(label: "Old key", value: "EXAMPLE")))]
        doc.siteIcons = ["example.com": Data([1, 2, 3])]
        let back = try JSONDecoder().decode(VaultDocument.self, from: JSONEncoder().encode(doc))
        #expect(back == doc)
        #expect(back.keys.first?.icon == .service("cloudflare"))
    }

    @Test("Recently Deleted keeps things for 30 days")
    func trashPurge() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var doc = VaultDocument()
        doc.trashed = [
            TrashEntry(.kept(KeptItem(label: "Fresh", value: "EXAMPLE")), deletedAt: now.addingTimeInterval(-29 * 86_400)),
            TrashEntry(.kept(KeptItem(label: "Stale", value: "EXAMPLE")), deletedAt: now.addingTimeInterval(-31 * 86_400)),
        ]
        #expect(doc.purgeTrash(now: now) == 1)
        #expect(doc.trashed.map(\.item.title) == ["Fresh"])
        doc.purgeTrash(now: now.addingTimeInterval(2 * 86_400))
        #expect(doc.trash == nil)
    }
}

@Suite("Links")
struct LinkTests {
    @Test func normalizes() {
        #expect(Links.normalized("dash.cloudflare.com") == "https://dash.cloudflare.com")
        #expect(Links.normalized("http://example.com/keys") == "https://example.com/keys")
        #expect(Links.normalized("  https://github.com/settings/tokens ") == "https://github.com/settings/tokens")
        #expect(Links.normalized("javascript:alert(1)") == nil)
        #expect(Links.normalized("ftp://example.com") == nil)
        #expect(Links.normalized("not a link") == nil)
        #expect(Links.normalized("localhost") == nil)
        #expect(Links.host(of: "https://www.GitHub.com/x") == "github.com")
    }
}
