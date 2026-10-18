import Foundation

/// One line of the Activity log. Names only: never a value or anything derived from one.
public struct ActivityEntry: Codable, Identifiable, Hashable, Sendable {
    public enum Action: String, Codable, Sendable {
        case copied, codeUsed, ran, exported, xcconfig, requested, guarded, leakFound, pushed, notarized, rotated
    }

    public var id: UUID
    public var date: Date
    public var action: Action
    /// The item or variable names involved.
    public var names: [String]
    /// Who asked: "You", "Claude Code", "Terminal", "Xcode"…
    public var actor: String
    /// A short plain description: the command's name and project, or where a leak was found.
    public var detail: String

    public static let limit = 1000

    public init(action: Action, names: [String], actor: String = "You", detail: String = "", date: Date = .now) {
        self.id = UUID()
        self.date = date
        self.action = action
        self.names = names
        self.actor = actor
        self.detail = detail
    }
}

/// A small secret file kept inside the vault (an App Store Connect .p8 key, a certificate, a service-account JSON).
public struct SecretFile: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case appStoreConnectKey, certificate, serviceAccount, other

        public var title: String {
            switch self {
            case .appStoreConnectKey: "App Store Connect API key"
            case .certificate: "Certificate or private key"
            case .serviceAccount: "Service account"
            case .other: "File"
            }
        }
    }

    public var id: UUID
    public var name: String
    public var filename: String
    public var kind: Kind
    public var data: Data
    /// Plain details that aren't secret, like an App Store Connect Issuer ID and Key ID.
    public var fields: [String: String]
    public var note: String?
    public var link: String?
    public var icon: IconChoice?
    /// Where it lives: the catalog id of the service the person manages it at (say "cloudflare"). Chosen by the
    /// person, so it beats any guess. nil means Slinky works it out from the name and link.
    public var service: String?
    public var created: Date
    public var updated: Date

    /// Files bigger than this are probably not secrets and don't belong in the vault.
    public static let maxBytes = 256 * 1024

    public init(name: String, filename: String, kind: Kind, data: Data, fields: [String: String] = [:], note: String? = nil) {
        self.id = UUID()
        self.name = name
        self.filename = filename
        self.kind = kind
        self.data = data
        self.fields = fields
        self.note = note
        self.created = .now
        self.updated = .now
    }

    /// What a dropped or picked file most likely is, from its name and first bytes.
    public static func guessKind(filename: String, data: Data) -> Kind {
        let lower = filename.lowercased()
        let head = String(decoding: data.prefix(200), as: UTF8.self)
        if lower.hasPrefix("authkey_") && lower.hasSuffix(".p8") { return .appStoreConnectKey }
        if lower.hasSuffix(".p8") { return .appStoreConnectKey }
        if lower.hasSuffix(".json"), head.contains("\"type\""), String(decoding: data, as: UTF8.self).contains("\"private_key\"") { return .serviceAccount }
        if [".p12", ".pem", ".key", ".cer", ".crt"].contains(where: lower.hasSuffix) || head.contains("-----BEGIN") { return .certificate }
        return .other
    }

    /// App Store Connect names its keys AuthKey_<KEYID>.p8.
    public static func keyID(fromFilename filename: String) -> String? {
        let base = (filename as NSString).deletingPathExtension
        guard base.hasPrefix("AuthKey_") else { return nil }
        let id = String(base.dropFirst("AuthKey_".count))
        return id.count >= 8 ? id : nil
    }
}
