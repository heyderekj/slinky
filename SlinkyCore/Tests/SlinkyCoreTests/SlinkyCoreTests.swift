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

    /// Short values never show most of themselves: at least 8 characters and half the value stay hidden.
    @Test func peekHidesShortValues() {
        for value in ["sk_live_xyz", "sk_live_EXAMPL", "ab-EXAMPLE12", "EXAMPLE12345", "rk_EXAMPLE_1234", "sk_live_EXAMPLE9Zx"] {
            let peek = Peek.of(value)
            let shown = peek.filter { $0 != "•" && $0 != "…" }.count
            #expect(value.count - shown >= max(8, value.count / 2), "\(value) → \(peek)")
        }
        #expect(Peek.of("sk_live_xyz") == "••••••••")
        #expect(Peek.of("EXAMPLE12345") == "••••…2345")
    }

    /// What people actually paste: invisible characters, backticks or quotes around a line, a shell prompt.
    @Test func envLineWithWrapping() throws {
        for paste in ["VERUM_SETUP_TEST=EXAMPLE", "\u{200B}VERUM_SETUP_TEST=EXAMPLE", "`VERUM_SETUP_TEST=EXAMPLE`",
                      "\"VERUM_SETUP_TEST=EXAMPLE\"", "“VERUM_SETUP_TEST=EXAMPLE”", "$ export VERUM_SETUP_TEST=EXAMPLE", "\u{FEFF}VERUM_SETUP_TEST=EXAMPLE\u{200D}"] {
            let d = try #require(Detector.detect(paste), "\(paste)")
            guard case let .envLines(lines) = d.kind else { Issue.record("not env: \(paste)"); continue }
            #expect(lines.map(\.name) == ["VERUM_SETUP_TEST"])
            #expect(lines.first?.value == "EXAMPLE")
            #expect(d.suggestedName == "VERUM_SETUP_TEST")
        }
        // A quoted value keeps working as before.
        #expect(DotEnv.parse("NAME=\"EXAMPLE value\"").first?.value == "EXAMPLE value")
    }

    @Test func duplicateExpectedNames() {
        #expect(DotEnv.names("A=\nB=\nA=\n") == ["A", "B"])
        let project = Project(name: "EXAMPLE", variables: [Variable(name: "B", values: [.local: "EXAMPLE"])], expected: ["A", "A", "B", "C"])
        #expect(project.missing == ["A", "C"])
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

    @Test func multiLineQuotedValues() {
        let text = """
        FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----
        MIIEXAMPLEEXAMPLE
        # not a comment, part of the key
        -----END PRIVATE KEY-----"
        NEXT=EXAMPLE
        SINGLE='line one
        line two'
        """
        let lines = DotEnv.parse(text)
        #expect(lines.map(\.name) == ["FIREBASE_PRIVATE_KEY", "NEXT", "SINGLE"])
        #expect(lines[0].value == "-----BEGIN PRIVATE KEY-----\nMIIEXAMPLEEXAMPLE\n# not a comment, part of the key\n-----END PRIVATE KEY-----")
        #expect(lines[1].value == "EXAMPLE")
        #expect(lines[1].group == nil)
        #expect(lines[2].value == "line one\nline two")
    }

    @Test func strayQuoteDoesNotSwallowTheRest() {
        let lines = DotEnv.parse("BROKEN=\"EXAMPLE\nNEXT=EXAMPLE2\nLAST='x'")
        #expect(lines.map(\.name) == ["BROKEN", "NEXT", "LAST"])
        #expect(lines[0].value == "EXAMPLE")
        #expect(lines[1].value == "EXAMPLE2")
    }

    @Test func escapesAndLineEndings() {
        let lines = DotEnv.parse("A=\"say \\\"EXAMPLE\\\" now\"\r\nB=EXAMPLE\r\nC=`back EXAMPLE`")
        #expect(lines.map(\.name) == ["A", "B", "C"])
        #expect(lines[0].value == "say \"EXAMPLE\" now")
        #expect(lines[1].value == "EXAMPLE")
        #expect(lines[2].value == "back EXAMPLE")
    }

    @Test func renderRoundTrips() {
        let pairs = [("PEM", "-----BEGIN EXAMPLE-----\nabc\n-----END EXAMPLE-----"), ("Q", "a \"quoted\" EXAMPLE"), ("P", "plainEXAMPLE")]
        let back = DotEnv.parse(DotEnv.render(pairs))
        #expect(back.map(\.name) == pairs.map(\.0))
        #expect(back.map(\.value) == pairs.map(\.1))
        #expect(!DotEnv.render(pairs).components(separatedBy: "\n").contains { $0.hasPrefix("abc") })
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

    @Test func backupRoundTrip() throws {
        let url = tempURL()
        let store = VaultStore(url: url, enclave: SoftwareWrapper())
        var (session, recovery) = try store.create()
        session.document.keys.append(Key(name: "STRIPE_SECRET_KEY", value: "sk_test_EXAMPLE"))
        try store.save(session)

        let backup = url.deletingLastPathComponent().appendingPathComponent("Slinky Backup.slinkybackup")
        try store.exportBackup(for: session, to: backup)
        #expect(VaultStore.isVaultFile(backup))
        #expect(!(try String(contentsOf: backup, encoding: .utf8)).contains("sk_test_EXAMPLE"))

        // A new Mac: no vault yet. The wrong key changes nothing; the right one restores and sets up Touch ID.
        let otherURL = tempURL()
        let newMac = VaultStore(url: otherURL, enclave: SoftwareWrapper())
        #expect(throws: VaultError.wrongRecoveryKey) { try newMac.restoreBackup(from: backup, recovery: RecoveryKey.generate()) }
        #expect(!newMac.exists)
        let restored = try newMac.restoreBackup(from: backup, recovery: recovery)
        #expect(restored.document == session.document)
        #expect(try newMac.unlock(context: nil).document == session.document)
        #expect(try newMac.unlock(recovery: recovery).document == session.document)
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
                let url = dir.appendingPathComponent(name)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: url, atomically: true, encoding: .utf8)
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

    @Test func skipsToolFilesAndReadsEveryExampleSuffix() throws {
        let dir = try folder([
            ".env": "A=EXAMPLE",
            ".env.vault": "DOTENV_VAULT_EXAMPLE=x",
            ".env.keys": "DOTENV_PRIVATE_KEY=EXAMPLE",
            ".env.sample": "A=\nB=",
            ".env.local.template": "C=",
        ])
        let scan = ProjectScan.scan(dir)
        #expect(scan.envFiles.map(\.fileName) == [".env"])
        #expect(Set(scan.skippedFiles) == [".env.vault", ".env.keys"])
        #expect(Set(scan.examples.map(\.id)) == [".env.sample", ".env.local.template"])
        #expect(Set(scan.expected) == ["A", "B", "C"])
    }

    @Test func monorepo() throws {
        let dir = try folder([
            "apps/web/": "", "packages/db/": "", "node_modules/x/": "", "apps/web/deep/er/still/": "", ".env/": "",
            ".env.local": "ROOT=EXAMPLE",
            "apps/web/.env.local": "WEB=EXAMPLE",
            "apps/web/.env.example": "WEB=\nWEB_EXTRA=",
            "packages/db/.env": "DB=EXAMPLE",
            "node_modules/x/.env": "NOPE=EXAMPLE",
            "apps/web/deep/er/still/.env": "TOO_DEEP=EXAMPLE",
        ])
        #expect(ProjectScan.scan(dir).envFiles.map(\.id) == [".env.local"])
        let scan = ProjectScan.scan(dir, depth: 3)
        #expect(scan.envFiles.map(\.id) == [".env.local", "apps/web/.env.local", "packages/db/.env"])
        #expect(scan.envFiles[1].folder == "apps/web")
        #expect(scan.groups == ["", "apps/web", "packages/db"])
        #expect(scan.expected == ["WEB", "WEB_EXTRA"])
        #expect(ProjectScan.expectedNames(inFolders: [dir]) == ["WEB", "WEB_EXTRA"])
    }

    @Test func nestedGitignore() throws {
        let dir = try folder([
            ".git/": "", "apps/web/": "", "apps/api/": "",
            ".gitignore": "/apps/api/.env\n",
            "apps/web/.gitignore": ".env*.local\n",
            "apps/web/.env.local": "A=EXAMPLE",
            "apps/web/.env.production": "A=EXAMPLE",
            "apps/api/.env": "A=EXAMPLE",
        ])
        let scan = ProjectScan.scan(dir, depth: 2)
        func ignored(_ id: String) -> Bool? { scan.envFiles.first { $0.id == id }?.ignoredByGit }
        #expect(ignored("apps/web/.env.local") == true)
        #expect(ignored("apps/web/.env.production") == false)
        #expect(ignored("apps/api/.env") == true)
    }

    @Test func findsKeyFiles() throws {
        let big = String(repeating: "x", count: SecretFile.maxBytes + 10)
        let dir = try folder([
            "keys/": "", "test/fixtures/": "",
            "keys/AuthKey_EXAMPLE123.p8": "-----BEGIN PRIVATE KEY-----\nEXAMPLE\n-----END PRIVATE KEY-----",
            "keys/server.pem": "-----BEGIN RSA PRIVATE KEY-----\nEXAMPLE\n-----END RSA PRIVATE KEY-----",
            "keys/public.pem": "-----BEGIN CERTIFICATE-----\nEXAMPLE\n-----END CERTIFICATE-----",
            "service-account.json": #"{"type": "service_account", "private_key": "-----BEGIN PRIVATE KEY-----EXAMPLE"}"#,
            "package.json": #"{"name": "example"}"#,
            "huge.pem": "-----BEGIN PRIVATE KEY-----" + big,
            "test/fixtures/sample.pem": "-----BEGIN PRIVATE KEY-----\nEXAMPLE",
        ])
        let scan = ProjectScan.scan(dir, depth: 3, secretFiles: true)
        #expect(Set(scan.secretFiles.map(\.id)) == ["keys/AuthKey_EXAMPLE123.p8", "keys/server.pem", "service-account.json",
                                                    "test/fixtures/sample.pem"])
        #expect(scan.secretFiles.first { $0.id == "test/fixtures/sample.pem" }?.likelyFixture == true)
        #expect(scan.secretFiles.first { $0.id == "keys/server.pem" }?.likelyFixture == false)
        #expect(ProjectScan.scan(dir, depth: 3).secretFiles.isEmpty)
    }

    @Test func hintsAndPrecedence() throws {
        #expect(ProjectScan.environmentHint(for: ".env") == nil)
        #expect(ProjectScan.environmentHint(for: ".env.production.local") == .production)
        #expect(ProjectScan.environmentHint(for: ".env.staging") == .preview)
        #expect(ProjectScan.environmentHint(for: ".env.development") == .local)
        #expect(ProjectScan.precedence(of: ".env") < ProjectScan.precedence(of: ".env.production"))
        #expect(ProjectScan.precedence(of: ".env.production") < ProjectScan.precedence(of: ".env.local"))
        #expect(ProjectScan.precedence(of: ".env.local") < ProjectScan.precedence(of: ".env.production.local"))
        let dir = try folder([".env.staging": "A=EXAMPLE"])
        let one = ProjectScan.scan(file: dir.appendingPathComponent(".env.staging"))
        #expect(one.envFiles.map(\.environment) == [.preview])
    }

    @Test func gitignoreNegationAndAnchors() {
        #expect(ProjectScan.isIgnored(".env", by: ["/.env"]))
        #expect(ProjectScan.isIgnored(".env.local", by: [".env*"]))
        #expect(!ProjectScan.isIgnored(".env.local", by: [".env*", "!.env.local"]))
        #expect(ProjectScan.isIgnored(".env.production", by: ["**/.env.*"]))
    }
}

@Suite("Folder changes")
struct FolderChangesTests {
    private func source(_ id: String, _ env: AppEnvironment, _ text: String) -> FolderChanges.Source {
        FolderChanges.Source(id: id, environment: env, lines: DotEnv.parse(text),
                             precedence: ProjectScan.precedence(of: (id as NSString).lastPathComponent))
    }

    private var project: Project {
        var p = Project(name: "harbor", expected: ["OLD_NAME"])
        p.variables = [
            Variable(name: "SAME", values: [.local: "EXAMPLE_same", .production: "EXAMPLE_prod"]),
            Variable(name: "CHANGES", values: [.local: "EXAMPLE_old"]),
            Variable(name: "ONLY_PROD", values: [.production: "EXAMPLE_p"]),
            Variable(name: "ONLY_HERE", values: [.local: "EXAMPLE_here"]),
        ]
        return p
    }

    @Test func classifiesEachRow() {
        let changes = FolderChanges.compare(project, with: [
            source(".env.local", .local, "SAME=EXAMPLE_same\nCHANGES=EXAMPLE_new\nBRAND_NEW=EXAMPLE_b\nONLY_PROD=EXAMPLE_l"),
        ], expected: ["SAME", "BRAND_NEW"])
        func status(_ name: String) -> EnvChange.Status? { changes.changes.first { $0.name == name }?.status() }
        #expect(status("SAME") == .same)
        #expect(status("CHANGES") == .changed)
        #expect(status("BRAND_NEW") == .new)
        #expect(status("ONLY_PROD") == .new)   // new in Local, though it exists in Production
        #expect(changes.changes.first { $0.name == "ONLY_PROD" }?.variableExists == true)
        #expect(status("ONLY_HERE") == .onlyInSlinky)
        // Production wasn't touched by any file, so nothing there is listed.
        #expect(!changes.changes.contains { $0.environment == .production })
        #expect(changes.expectedAdded == ["SAME", "BRAND_NEW"])
        #expect(changes.expectedRemoved == ["OLD_NAME"])
    }

    @Test func defaultsSkipBlanksAndPickTheMoreSpecificFile() {
        let changes = FolderChanges.compare(project, with: [
            source(".env", .local, "CHANGES=\nNEW_ONE=EXAMPLE_root\nAGREE=EXAMPLE_same"),
            source(".env.local", .local, "NEW_ONE=EXAMPLE_local\nAGREE=EXAMPLE_same"),
        ])
        let picks = changes.defaultPicks
        let blank = changes.changes.first { $0.name == "CHANGES" }!
        #expect(blank.status() == .changed)
        #expect(!picks.rows.contains(blank.id))
        let conflict = changes.changes.first { $0.name == "NEW_ONE" }!
        #expect(conflict.isConflict)
        #expect(conflict.offer()?.source == ".env.local")
        #expect(conflict.offer(picking: ".env")?.value == "EXAMPLE_root")
        #expect(!changes.changes.first { $0.name == "AGREE" }!.isConflict)
    }

    @Test func firstGroupWinsAcrossSubfolders() {
        let changes = FolderChanges.compare(Project(name: "mono"), with: [
            source("apps/web/.env", .local, "SHARED=EXAMPLE_web"),
            source("apps/api/.env.local", .local, "SHARED=EXAMPLE_api"),
        ])
        #expect(changes.changes.first?.offer()?.source == "apps/web/.env")
    }

    @Test func applyNeverRemovesAndCounts() {
        var p = project
        let changes = FolderChanges.compare(p, with: [
            source(".env.local", .local, "SAME=EXAMPLE_same\nCHANGES=EXAMPLE_new\nBRAND_NEW=EXAMPLE_b\nNEXT_PUBLIC_URL=https://example.com\nLEFT_OUT=EXAMPLE_x"),
        ], expected: ["SAME", "BRAND_NEW"])
        var picks = changes.defaultPicks
        picks.rows.remove("local|LEFT_OUT")
        let summary = changes.apply(picks, to: &p, replaceExpected: true)
        #expect(summary == FolderChanges.Summary(new: 2, updated: 1, unchanged: 1, skipped: 1))
        #expect(summary.text == "2 new, 1 updated, 1 unchanged, 1 skipped")
        #expect(p.variables.first { $0.name == "CHANGES" }?.value(in: .local) == "EXAMPLE_new")
        #expect(p.variables.first { $0.name == "ONLY_HERE" }?.value(in: .local) == "EXAMPLE_here")
        #expect(p.variables.first { $0.name == "SAME" }?.value(in: .production) == "EXAMPLE_prod")
        #expect(p.variables.first { $0.name == "NEXT_PUBLIC_URL" }?.isPlain == true)
        #expect(p.variables.first { $0.name == "BRAND_NEW" }?.isPlain == false)
        #expect(!p.variables.contains { $0.name == "LEFT_OUT" })
        #expect(p.expected == ["SAME", "BRAND_NEW"])
    }

    @Test func aNewProjectIsAllNew() {
        let changes = FolderChanges.compare(Project(name: "fresh"), with: [
            source(".env", .local, "A=EXAMPLE\nB=EXAMPLE"), source(".env.production", .production, "A=EXAMPLE_p"),
        ])
        #expect(changes.changes.allSatisfy { $0.status() == .new })
        var p = Project(name: "fresh")
        #expect(changes.apply(changes.defaultPicks, to: &p).text == "2 new")
        #expect(p.variables.first { $0.name == "A" }?.value(in: .production) == "EXAMPLE_p")
    }

    @Test func emptySummary() {
        #expect(FolderChanges.Summary().text == "Nothing to change")
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

    @Test("Imports and unknown actions from a newer Slinky round-trip without breaking the vault")
    func activityActionsAreTolerant() throws {
        var doc = VaultDocument()
        let id = UUID()
        doc.log = [ActivityEntry(action: .imported, names: ["API_KEY"], detail: "harbor, from ~/EXAMPLE", itemIDs: [id])]
        let back = try JSONDecoder().decode(VaultDocument.self, from: JSONEncoder().encode(doc))
        #expect(back.log.first?.action == .imported)
        #expect(back.log.first?.itemIDs == [id])
        let future = #"{"activity":[{"id":"7B1B3C2E-0000-4000-8000-000000000009","date":800000000,"action":"teleported","names":["X"],"actor":"You","detail":""}],"formatVersion":2,"projects":[],"keys":[],"codeSets":[],"kept":[]}"#
        let opened = try JSONDecoder().decode(VaultDocument.self, from: Data(future.utf8))
        #expect(opened.log.first?.action == .other)
    }

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

@Suite("Services")
struct ServiceTests {
    @Test func namesPickTheService() {
        #expect(ServiceCatalog.match(name: "GITHUB_TOKEN")?.id == "github")
        #expect(ServiceCatalog.match(name: "GitHubToken")?.id == "github")
        #expect(ServiceCatalog.match(name: "STRIPE_SECRET_KEY")?.id == "stripe")
        #expect(ServiceCatalog.match(name: "HF_TOKEN")?.id == "huggingface")
        #expect(ServiceCatalog.match(name: "Hugging Face")?.id == "huggingface")
        #expect(ServiceCatalog.match(name: "Google Cloud key")?.id == "googlecloud")
        #expect(ServiceCatalog.match(name: "Apple Account recovery key")?.id == "apple")
        #expect(ServiceCatalog.match(name: "Acme deploy key") == nil)
        #expect(ServiceCatalog.match(name: "PINEAPPLE_KEY") == nil)
    }

    @Test func providersAndLinksWin() {
        #expect(ServiceCatalog.match(name: "DEPLOY_KEY", provider: "AWS")?.id == "aws")
        #expect(ServiceCatalog.match(name: "TOKEN", link: "https://dash.cloudflare.com/profile")?.id == "cloudflare")
        #expect(ServiceCatalog.match(name: "GITHUB_TOKEN", link: "https://vercel.com/account")?.id == "vercel")
        #expect(ServiceCatalog.match(name: "Codes", from: "gitlab.com")?.id == "gitlab")
        #expect(ServiceCatalog.match(name: "Key", note: "Made at console.anthropic.com for the bot")?.id == "anthropic")
    }

    @Test func catalogIsConsistent() {
        #expect(Set(ServiceCatalog.all.map(\.id)).count == ServiceCatalog.all.count)
        #expect(ServiceCatalog.service(forHost: "gist.github.com")?.id == "github")
        #expect(ServiceCatalog.all.filter(\.hasLogo).allSatisfy { $0.color != nil })
    }
}

@Suite("Agents and CLI")
struct BrokerTests {
    @Test func agentsCantRunShellsOrSendThingsOff() {
        #expect(Broker.agentRefusal(["npm", "run", "dev"]) == nil)
        #expect(Broker.agentRefusal(["make", "test"]) == nil)
        #expect(Broker.agentRefusal(["env"]) != nil)
        #expect(Broker.agentRefusal(["/usr/bin/printenv"]) != nil)
        #expect(Broker.agentRefusal(["sh", "-c", "echo $KEY"]) != nil)
        #expect(Broker.agentRefusal(["node", "-e", "console.log(process.env)"]) != nil)
        #expect(Broker.agentRefusal(["node", "server.js"]) == nil)
        #expect(Broker.agentRefusal(["curl", "https://example.com"]) != nil)
        #expect(Broker.agentRefusal(["git", "push"]) != nil)
        #expect(Broker.agentRefusal(["npm", "publish"]) != nil)
    }

    @Test func injectionVariablesAreStripped() {
        #expect(Broker.isStripped("NODE_OPTIONS"))
        #expect(Broker.isStripped("DYLD_INSERT_LIBRARIES"))
        #expect(!Broker.isStripped("STRIPE_SECRET_KEY"))
    }

    @Test func shellExportsQuoteAnything() {
        let out = Broker.shellExports(["A_KEY": "it's EXAMPLE $HOME `x`"])
        #expect(out.contains(#"export A_KEY='it'\''s EXAMPLE $HOME `x`'"#))
        #expect(out.contains("export _SLINKY_NAMES='A_KEY'"))
    }

    @Test func xcconfigKeepsURLs() {
        let out = Broker.xcconfig(["API_URL": "https://api.example.com"], project: "Demo")
        #expect(out.contains("API_URL = https:/$()/api.example.com"))
    }

    @Test func pathsInsideLinkedFolders() {
        #expect(Broker.path("/tmp/demo/src", isInside: ["/tmp/demo"]))
        #expect(!Broker.path("/tmp/demo2", isInside: ["/tmp/demo"]))
    }
}

@Suite("Leak finder")
struct LeakTests {
    let secrets = [LeakScanner.Secret(name: "STRIPE_SECRET_KEY", value: "sk_test_EXAMPLE1234"),
                   LeakScanner.Secret(name: "SHORT", value: "abc")]

    @Test func findsExactValuesOnly() {
        #expect(LeakScanner.matches(in: "key=sk_test_EXAMPLE1234 and abc", secrets: secrets) == ["STRIPE_SECRET_KEY"])
        #expect(LeakScanner.matches(in: "sk_test_EXAMPLE123", secrets: secrets).isEmpty)
    }

    @Test func cleansHistory() {
        let (text, removed) = LeakScanner.removingLines(containing: ["sk_test_EXAMPLE1234"], from: "ls\nexport K=sk_test_EXAMPLE1234\ngit status")
        #expect(removed == 1)
        #expect(text == "ls\ngit status")
        #expect(LeakScanner.lines(of: "git", in: "ls\ngit status") == [2])
    }
}

@Suite("Secret files")
struct SecretFileTests {
    @Test func recognisesAppStoreConnectKeys() {
        let p8 = Data("-----BEGIN PRIVATE KEY-----\nEXAMPLE\n-----END PRIVATE KEY-----\n".utf8)
        #expect(SecretFile.guessKind(filename: "AuthKey_ABCD1234EF.p8", data: p8) == .appStoreConnectKey)
        #expect(SecretFile.keyID(fromFilename: "AuthKey_ABCD1234EF.p8") == "ABCD1234EF")
        #expect(SecretFile.guessKind(filename: "dev.pem", data: p8) == .certificate)
        #expect(SecretFile.guessKind(filename: "sa.json", data: Data(#"{"type": "service_account", "private_key": "EXAMPLE"}"#.utf8)) == .serviceAccount)
    }
}

@Suite("Apple developer")
struct AppleDeveloperTests {
    @Test func appSpecificPassword() {
        let d = Detector.detect("abcd-efgh-ijkl-mnop")
        #expect(d?.provider == "Apple")
        #expect(d?.suggestedName == "APPLE_APP_SPECIFIC_PASSWORD")
    }

    @Test func fileVariables() {
        #expect(Broker.fileVariable("App Store Connect API key") == ("App Store Connect API key", "APP_STORE_CONNECT_API_KEY_PATH"))
        #expect(Broker.fileVariable("Push cert=APNS_KEY_PATH") == ("Push cert", "APNS_KEY_PATH"))
    }
}
