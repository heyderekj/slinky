import Foundation

/// What a pasted value looks like, and where it probably belongs.
/// Patterns are a small, hand-picked subset in the spirit of gitleaks (MIT). They're hints, never verdicts.
public struct Detection: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case apiKey          // a service key or token → Keys, or a project variable
        case recoveryKey     // Apple ID / FileVault style → Recovery
        case setupKey        // otpauth:// → Recovery
        case recoveryCodes([String])  // a block of 2FA backup codes → Codes
        case envLines([DotEnvLine])   // KEY=value lines → a project
        case plainConfig     // publishable / public values → a plain project variable
        case walletSeed      // refused, politely
        case unknown
    }

    public enum Destination: String, CaseIterable, Sendable {
        case key, project, codes, kept
        public var title: String {
            switch self {
            case .key: "Key or Token"
            case .project: "Project Variable"
            case .codes: "Recovery Codes"
            case .kept: "Recovery Key"
            }
        }
    }

    public var kind: Kind
    public var provider: String?
    /// One-liner in Slinky's voice: "Looks like a Stripe live key."
    public var label: String
    public var suggestedName: String?
    public var isLive: Bool = false

    public var destination: Destination {
        switch kind {
        case .apiKey, .unknown: .key
        case .recoveryKey, .setupKey, .walletSeed: .kept
        case .recoveryCodes: .codes
        case .envLines, .plainConfig: .project
        }
    }
}

public enum Detector {
    private struct Rule: Sendable {
        let pattern: String
        let provider: String
        let label: String
        let name: String
        var live: Bool = false
        var plain: Bool = false
    }

    // Order matters: first match wins.
    private static let rules: [Rule] = [
        Rule(pattern: #"^sk_live_[A-Za-z0-9]{8,}"#, provider: "Stripe", label: "Looks like a Stripe live key.", name: "STRIPE_SECRET_KEY", live: true),
        Rule(pattern: #"^sk_test_[A-Za-z0-9]{8,}"#, provider: "Stripe", label: "Looks like a Stripe test key.", name: "STRIPE_SECRET_KEY"),
        Rule(pattern: #"^rk_(live|test)_[A-Za-z0-9]{8,}"#, provider: "Stripe", label: "Looks like a Stripe restricted key.", name: "STRIPE_RESTRICTED_KEY"),
        Rule(pattern: #"^whsec_[A-Za-z0-9]{8,}"#, provider: "Stripe", label: "Looks like a Stripe webhook secret.", name: "STRIPE_WEBHOOK_SECRET"),
        Rule(pattern: #"^pk_(live|test)_[A-Za-z0-9]{8,}"#, provider: "Stripe", label: "Looks like a Stripe publishable key. These are public, not secret.", name: "NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY", plain: true),
        Rule(pattern: #"^sk-ant-[A-Za-z0-9_\-]{8,}"#, provider: "Anthropic", label: "Looks like an Anthropic key.", name: "ANTHROPIC_API_KEY"),
        Rule(pattern: #"^sk-(proj|svcacct|admin)-[A-Za-z0-9_\-]{8,}"#, provider: "OpenAI", label: "Looks like an OpenAI key.", name: "OPENAI_API_KEY"),
        Rule(pattern: #"^sk-[A-Za-z0-9]{20,}"#, provider: "OpenAI", label: "Looks like an OpenAI key.", name: "OPENAI_API_KEY"),
        Rule(pattern: #"^re_[A-Za-z0-9_]{8,}"#, provider: "Resend", label: "Looks like a Resend key.", name: "RESEND_API_KEY"),
        Rule(pattern: #"^github_pat_[A-Za-z0-9_]{20,}"#, provider: "GitHub", label: "Looks like a GitHub personal token.", name: "GITHUB_TOKEN"),
        Rule(pattern: #"^gh[pousr]_[A-Za-z0-9]{20,}"#, provider: "GitHub", label: "Looks like a GitHub token.", name: "GITHUB_TOKEN"),
        Rule(pattern: #"^(AKIA|ASIA)[A-Z0-9]{16}$"#, provider: "AWS", label: "Looks like an AWS access key.", name: "AWS_ACCESS_KEY_ID"),
        Rule(pattern: #"^AIza[0-9A-Za-z_\-]{30,}"#, provider: "Google", label: "Looks like a Google API key.", name: "GOOGLE_API_KEY"),
        Rule(pattern: #"^hf_[A-Za-z0-9]{20,}"#, provider: "Hugging Face", label: "Looks like a Hugging Face token.", name: "HF_TOKEN"),
        Rule(pattern: #"^xox[abpr]-[A-Za-z0-9\-]{10,}"#, provider: "Slack", label: "Looks like a Slack token.", name: "SLACK_BOT_TOKEN"),
        Rule(pattern: #"^sb_secret_[A-Za-z0-9_\-]{8,}"#, provider: "Supabase", label: "Looks like a Supabase secret key.", name: "SUPABASE_SECRET_KEY"),
        Rule(pattern: #"^sb_publishable_[A-Za-z0-9_\-]{8,}"#, provider: "Supabase", label: "Looks like a Supabase publishable key. These are public, not secret.", name: "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", plain: true),
        Rule(pattern: #"^nfp_[A-Za-z0-9]{8,}"#, provider: "Netlify", label: "Looks like a Netlify token.", name: "NETLIFY_AUTH_TOKEN"),
        Rule(pattern: #"^vercel_[A-Za-z0-9]{8,}"#, provider: "Vercel", label: "Looks like a Vercel token.", name: "VERCEL_TOKEN"),
        Rule(pattern: #"^phc_[A-Za-z0-9]{8,}"#, provider: "PostHog", label: "Looks like a PostHog project key. These are public, not secret.", name: "NEXT_PUBLIC_POSTHOG_KEY", plain: true),
        Rule(pattern: #"^(postgres|postgresql|mysql|mongodb(\+srv)?|redis)://"#, provider: "Database", label: "Looks like a database URL.", name: "DATABASE_URL"),
        Rule(pattern: #"^eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+"#, provider: "JWT", label: "Looks like a JWT. Maybe a Supabase key.", name: "SUPABASE_SERVICE_ROLE_KEY"),
    ]

    public static func detect(_ raw: String) -> Detection? {
        let text = DotEnv.withoutInvisibles(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Multi-line pastes first: a .env block, or a block of recovery codes.
        if text.contains("\n") || text.contains("=") {
            let lines = DotEnv.parse(text)
            if !lines.isEmpty, lines.count * 2 >= text.split(whereSeparator: \.isNewline).filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("#") }).count {
                let label = lines.count == 1 ? "Looks like \(lines[0].name) for a project." : "Looks like \(lines.count) variables from a .env file."
                return Detection(kind: .envLines(lines), provider: nil, label: label, suggestedName: lines.count == 1 ? lines[0].name : nil)
            }
        }
        if isWalletSeed(text) {
            return Detection(kind: .walletSeed, provider: nil,
                             label: "This looks like a crypto wallet recovery phrase. For your safety, Slinky doesn't store these. Keep it on paper or a hardware wallet.", suggestedName: nil)
        }
        if text.lowercased().hasPrefix("otpauth://") {
            return Detection(kind: .setupKey, provider: nil, label: "Looks like a 2FA setup key.", suggestedName: "2FA setup key")
        }
        // Apple ID recovery key: 28 characters in 7 groups of 4.
        if text.range(of: #"^[A-Z0-9]{4}(-[A-Z0-9]{4}){6}$"#, options: .regularExpression) != nil {
            return Detection(kind: .recoveryKey, provider: "Apple", label: "Looks like an Apple recovery key.", suggestedName: "Apple ID recovery key")
        }
        // FileVault personal recovery key: 6 groups of 4.
        if text.range(of: #"^[A-Z0-9]{4}(-[A-Z0-9]{4}){5}$"#, options: .regularExpression) != nil {
            return Detection(kind: .recoveryKey, provider: "Apple", label: "Looks like a FileVault recovery key.", suggestedName: "FileVault recovery key")
        }
        // Apple app-specific password (notarization, Xcode, altool): 4 groups of 4 lowercase letters.
        if text.range(of: #"^[a-z]{4}-[a-z]{4}-[a-z]{4}-[a-z]{4}$"#, options: .regularExpression) != nil {
            return Detection(kind: .apiKey, provider: "Apple", label: "Looks like an Apple app-specific password, like the one notarization uses.",
                             suggestedName: "APPLE_APP_SPECIFIC_PASSWORD")
        }
        let codes = RecoveryCodes.extract(text)
        if codes.count >= 4 {
            return Detection(kind: .recoveryCodes(codes), provider: RecoveryCodes.guessProvider(text),
                             label: "Looks like \(codes.count) recovery codes.", suggestedName: nil)
        }
        for rule in rules where text.range(of: rule.pattern, options: .regularExpression) != nil {
            return Detection(kind: rule.plain ? .plainConfig : .apiKey, provider: rule.provider, label: rule.label,
                             suggestedName: rule.name, isLive: rule.live)
        }
        return Detection(kind: .unknown, provider: nil, label: "Slinky doesn't recognize this format. Give it a name below.", suggestedName: nil)
    }

    /// 12, 15, 18, 21 or 24 short lowercase words. We don't ship the BIP-39 word list; the shape is enough to say no.
    static func isWalletSeed(_ text: String) -> Bool {
        let words = text.lowercased().split(whereSeparator: { $0 == " " || $0 == "\n" })
        guard [12, 15, 18, 21, 24].contains(words.count) else { return false }
        return words.allSatisfy { w in (3...8).contains(w.count) && w.allSatisfy { $0.isLetter && $0.isASCII } }
    }
}

public enum RecoveryCodes {
    /// Pulls 2FA backup codes out of a pasted block: "a1b2c-3d4e5", "1234 5678", "ABCD-EFGH", or 8–12 char tokens one per line.
    public static func extract(_ text: String) -> [String] {
        let patterns = [
            #"\b[A-Za-z0-9]{4,6}-[A-Za-z0-9]{4,6}\b"#,     // GitHub, Vercel, npm style
            #"\b\d{4} \d{4}\b"#,                           // Google style
        ]
        for p in patterns {
            let found = matches(p, in: text)
            if found.count >= 4 { return found }
        }
        // One code per line, 8–12 alphanumerics.
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let tokens = lines.filter { $0.range(of: #"^[A-Za-z0-9]{8,12}$"#, options: .regularExpression) != nil }
        return tokens.count >= 4 ? tokens : []
    }

    public static func guessProvider(_ text: String) -> String? {
        let lower = text.lowercased()
        for name in ["GitHub", "Google", "Vercel", "Stripe", "npm", "Cloudflare", "Apple", "Discord", "Twitter", "Microsoft", "AWS", "Netlify", "Supabase", "Linear", "Figma", "Webflow"]
        where lower.contains(name.lowercased()) { return name }
        return nil
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        return re.matches(in: text, range: range).compactMap { m in
            guard let r = Range(m.range, in: text) else { return nil }
            let s = String(text[r])
            return seen.insert(s).inserted ? s : nil
        }
    }
}

public enum Peek {
    /// "sk_live_EXAMPLE…4f2a" → "sk_live_…4f2a". Enough to tell keys apart without exposing them. At least 8
    /// characters, and at least half the value, always stay hidden; a value too short for that shows as dots.
    public static func of(_ value: String) -> String {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let dots = String(repeating: "•", count: 8)
        guard v.count > 10 else { return dots }
        let tail = v.suffix(4)
        let minHidden = max(8, v.count / 2)
        // Keep a recognisable prefix up to the last "_" or "-" within the first 12 characters.
        let head = v.prefix(12)
        if let cut = head.lastIndex(where: { $0 == "_" || $0 == "-" }), head.distance(from: head.startIndex, to: cut) >= 1 {
            let shown = v.distance(from: v.startIndex, to: cut) + 1
            if v.count - shown - tail.count >= minHidden { return String(v[...cut]) + "…" + tail }
        }
        if v.count - tail.count >= minHidden { return "••••…" + tail }
        return dots
    }
}
