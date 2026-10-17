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
