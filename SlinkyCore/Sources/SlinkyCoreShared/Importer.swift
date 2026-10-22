import Compression
import Foundation

/// Reads an export from another app and finds what belongs in Slinky: API keys and tokens, recovery codes
/// and recovery keys. Website passwords and logins are skipped on purpose (they belong in Apple Passwords),
/// and so are crypto wallet phrases. Nothing is written to disk while reading.
public enum Importer {
    public struct Candidate: Identifiable, Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            case key(provider: String?, isLive: Bool, expires: Date?)
            case codes([String])
            case recoveryKey(KeptKind)
        }

        public let id = UUID()
        public var name: String
        public var kind: Kind
        /// The secret itself (for codes, the codes joined by newlines). Never shown in full.
        public var value: String
        /// Where it came from, for the list: "1Password · Personal".
        public var source: String
        public var note: String?

        public static func == (a: Candidate, b: Candidate) -> Bool { a.id == b.id }
    }

    public struct Result: Sendable {
        public var candidates: [Candidate] = []
        /// Logins and passwords left behind, so the import screen can say so.
        public var skippedPasswords = 0
        public var skippedOther = 0
    }

    public enum ImportError: Error, Equatable, CustomStringConvertible {
        case unreadable, notAnExport, unsupportedZip

        public var description: String {
            switch self {
            case .unreadable: "Slinky couldn't read that file."
            case .notAnExport: "Slinky can import .1pux and .csv files. That one isn't either."
            case .unsupportedZip: "Slinky couldn't open that export. Try exporting from 1Password again, as a .1pux file."
            }
        }
    }

    /// Reads a file by its extension: `.1pux` (1Password's export), `.csv` (1Password, Apple Passwords, Bitwarden,
    /// LastPass, KeePass, or a simple name,value sheet), or plain text (codes, KEY=value lines, a key).
    public static func read(_ url: URL) throws -> Result {
        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable }
        switch url.pathExtension.lowercased() {
        case "1pux":
            guard let json = try ZipReader.file(named: "export.data", in: data) else { throw ImportError.notAnExport }
            return try onePassword(json)
        case "csv", "txt", "env", "":
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { throw ImportError.unreadable }
            return csv(text, source: url.deletingPathExtension().lastPathComponent)
        default:
            throw ImportError.notAnExport
        }
    }

    // MARK: 1Password (.1pux)

    /// 1Password's category for API Credential items.
    static let apiCredentialCategory = "112"
    static let passwordCategories: Set<String> = ["001", "005"]   // Login, Password

    public static func onePassword(_ json: Data) throws -> Result {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let accounts = root["accounts"] as? [[String: Any]] else { throw ImportError.notAnExport }
        var result = Result()
        for account in accounts {
            for vault in account["vaults"] as? [[String: Any]] ?? [] {
                let vaultName = (vault["attrs"] as? [String: Any])?["name"] as? String ?? "Vault"
                let source = "1Password · \(vaultName)"
                for item in vault["items"] as? [[String: Any]] ?? [] {
                    if (item["state"] as? String) == "archived" || (item["trashed"] as? Bool) == true { continue }
                    let category = item["categoryUuid"] as? String ?? ""
                    let overview = item["overview"] as? [String: Any] ?? [:]
                    let title = (overview["title"] as? String)?.trimmingCharacters(in: .whitespaces) ?? "Untitled"
                    let details = item["details"] as? [String: Any] ?? [:]
                    let notes = details["notesPlain"] as? String ?? ""
                    let fields = sectionFields(details)
                    var found = false

                    if category == apiCredentialCategory {
                        let credential = fields.first { $0.id == "credential" || $0.concealed }?.value
                        if let credential, !credential.isEmpty {
                            let detection = Detector.detect(credential)
                            let expires = fields.first { $0.id == "expires" }?.date
                            result.candidates.append(Candidate(
                                name: title, kind: .key(provider: detection?.provider, isLive: detection?.isLive ?? false, expires: expires),
                                value: credential, source: source, note: nil))
                            found = true
                        }
                    } else {
                        // Any concealed field that's clearly a service key (not a password).
                        for field in fields where field.concealed {
                            if let detection = Detector.detect(field.value), detection.kind == .apiKey {
                                result.candidates.append(Candidate(
                                    name: detection.suggestedName ?? title,
                                    kind: .key(provider: detection.provider, isLive: detection.isLive, expires: nil),
                                    value: field.value, source: source, note: "From \(title)"))
                                found = true
                            }
                        }
                    }
                    // Notes often hold backup codes or a recovery key, and sometimes an API key or .env lines.
                    if let fromNotes = candidate(fromNotes: notes, title: title, source: source) {
                        result.candidates.append(fromNotes)
                        found = true
                    }
                    let known = Set(result.candidates.map(\.value))
                    let inNotes = keys(inNotes: notes, title: title, source: source).filter { !known.contains($0.value) }
                    if !inNotes.isEmpty { result.candidates += inNotes; found = true }
                    if !found {
                        if passwordCategories.contains(category) { result.skippedPasswords += 1 } else { result.skippedOther += 1 }
                    }
                }
            }
        }
        return result
    }

    private struct Field {
        let id: String
        let value: String
        let concealed: Bool
        let date: Date?
    }

    private static func sectionFields(_ details: [String: Any]) -> [Field] {
        var out: [Field] = []
        for section in details["sections"] as? [[String: Any]] ?? [] {
            for field in section["fields"] as? [[String: Any]] ?? [] {
                let id = field["id"] as? String ?? ""
                let value = field["value"] as? [String: Any] ?? [:]
                if let s = value["concealed"] as? String {
                    out.append(Field(id: id, value: s, concealed: true, date: nil))
                } else if let s = value["string"] as? String {
                    out.append(Field(id: id, value: s, concealed: false, date: nil))
                } else if let d = value["date"] as? Double {
                    out.append(Field(id: id, value: "", concealed: false, date: Date(timeIntervalSince1970: d)))
                }
            }
        }
        return out
    }

    // MARK: CSV

    /// Column names people use, lowercased. The first match wins.
    private static let nameColumns = ["title", "name", "label", "key name", "item", "account"]
    private static let valueColumns = ["value", "secret", "token", "api key", "apikey", "key", "credential", "password", "login_password"]
    private static let noteColumns = ["notes", "note", "comments", "extra"]   // extra: LastPass
    private static let urlColumns = ["url", "website", "login_uri", "urls", "web site"]   // web site: KeePass
    /// LastPass secure notes that are cards, IDs or records: never keys.
    private static let personalNoteTypes = ["credit card", "bank account", "passport", "social security", "driver's license",
                                            "insurance", "health insurance", "membership", "address"]

    public static func csv(_ text: String, source: String) -> Result {
        let rows = CSV.parse(text)
        guard let header = rows.first else { return Result() }
        let columns = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        func index(_ names: [String]) -> Int? {
            for n in names { if let i = columns.firstIndex(of: n) { return i } }
            return nil
        }
        let nameAt = index(nameColumns), valueAt = index(valueColumns), noteAt = index(noteColumns), urlAt = index(urlColumns)
        let typeAt = index(["type"]), fieldsAt = index(["fields"]), archivedAt = index(["archived"])
        // Not a table at all: a text file of codes, KEY=value lines or a key.
        guard nameAt != nil || valueAt != nil else { return plainText(text, source: source) }
        // A password-manager export has a URL or username column; a plain sheet of keys usually doesn't.
        let isPasswordExport = urlAt != nil || columns.contains("username") || columns.contains("login_username")
            || columns.contains("login name")

        var result = Result()
        for row in rows.dropFirst() where !row.allSatisfy({ $0.isEmpty }) {
            func cell(_ i: Int?) -> String { i.flatMap { $0 < row.count ? row[$0] : nil }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
            let title = cell(nameAt).isEmpty ? (cell(urlAt).isEmpty ? "Untitled" : cell(urlAt)) : cell(nameAt)
            // Bitwarden cards and identities, 1Password's archived rows, LastPass's personal notes: never keys.
            if ["card", "identity"].contains(cell(typeAt).lowercased())
                || ["true", "1", "yes"].contains(cell(archivedAt).lowercased())
                || personalNoteTypes.contains(where: { cell(noteAt).lowercased().hasPrefix("notetype:\($0)") }) {
                result.skippedOther += 1
                continue
            }
            let value = cell(valueAt)
            var found = false
            if !value.isEmpty, let detection = Detector.detect(value) {
                switch detection.kind {
                case .apiKey:
                    result.candidates.append(Candidate(
                        name: isPasswordExport ? (detection.suggestedName ?? title) : title,
                        kind: .key(provider: detection.provider, isLive: detection.isLive, expires: nil),
                        value: value, source: source, note: isPasswordExport ? "From \(title)" : nil))
                    found = true
                case .unknown where !isPasswordExport:
                    // A plain name,value sheet: trust the person's own label.
                    result.candidates.append(Candidate(name: title, kind: .key(provider: nil, isLive: false, expires: nil),
                                                       value: value, source: source, note: nil))
                    found = true
                case .recoveryKey:
                    result.candidates.append(Candidate(name: title, kind: .recoveryKey(.recoveryKey), value: value, source: source, note: nil))
                    found = true
                default:
                    break
                }
            }
            if let fromNotes = candidate(fromNotes: cell(noteAt), title: title, source: source) {
                result.candidates.append(fromNotes)
                found = true
            }
            // API keys in notes or in Bitwarden's custom fields ("Name: value" lines).
            let known = Set(result.candidates.map(\.value))
            let extra = (keys(inNotes: cell(noteAt), title: title, source: source)
                         + keys(inNotes: cell(fieldsAt), title: title, source: source)).filter { !known.contains($0.value) }
            if !extra.isEmpty { result.candidates += extra; found = true }
            if !found { if isPasswordExport { result.skippedPasswords += 1 } else { result.skippedOther += 1 } }
        }
        return result
    }

    // MARK: Plain text

    /// A text file with no table: a block of recovery codes, KEY=value lines, or a key on its own.
    static func plainText(_ text: String, source: String) -> Result {
        var result = Result()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !Detector.isWalletSeed(trimmed) else { return result }
        let codes = RecoveryCodes.extract(trimmed)
        if codes.count >= 4 {
            result.candidates.append(Candidate(name: source, kind: .codes(codes), value: codes.joined(separator: "\n"), source: source, note: nil))
            return result
        }
        for line in DotEnv.parse(trimmed) where !line.value.isEmpty {
            let detection = Detector.detect(line.value)
            result.candidates.append(Candidate(name: line.name, kind: .key(provider: detection?.provider, isLive: detection?.isLive ?? false, expires: nil),
                                               value: line.value, source: source, note: nil))
        }
        if result.candidates.isEmpty, let detection = Detector.detect(trimmed) {
            switch detection.kind {
            case .apiKey:
                result.candidates.append(Candidate(name: detection.suggestedName ?? source,
                                                   kind: .key(provider: detection.provider, isLive: detection.isLive, expires: nil),
                                                   value: trimmed, source: source, note: nil))
            case .recoveryKey:
                result.candidates.append(Candidate(name: source, kind: .recoveryKey(.recoveryKey), value: trimmed, source: source, note: nil))
            default:
                result.skippedOther += 1
            }
        }
        return result
    }

    // MARK: Shared

    /// API keys inside notes or custom fields: `NAME=value` lines, `Label: value` lines, or a token on its own.
    /// Only values Slinky recognizes as a service's key are kept. Anything else could be a password.
    public static func keys(inNotes notes: String, title: String, source: String) -> [Candidate] {
        let text = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !Detector.isWalletSeed(text) else { return [] }
        var out: [Candidate] = []
        var seen = Set<String>()
        func consider(_ value: String, label: String?) {
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'`")))
            guard v.count >= 12, !seen.contains(v), let d = Detector.detect(v), d.kind == .apiKey, d.provider != nil else { return }
            seen.insert(v)
            let name = label.flatMap { $0.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil ? $0 : nil }
                ?? d.suggestedName ?? title
            out.append(Candidate(name: name, kind: .key(provider: d.provider, isLive: d.isLive, expires: nil),
                                 value: v, source: source, note: "From \(title)"))
        }
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            if let env = DotEnv.parse(line).first {
                consider(env.value, label: env.name)
            } else if let colon = line.firstIndex(of: ":"), line[line.index(after: colon)...].hasPrefix(" ") {
                consider(String(line[line.index(after: colon)...]), label: line[..<colon].trimmingCharacters(in: .whitespaces))
            } else {
                for word in line.split(whereSeparator: \.isWhitespace) { consider(String(word), label: nil) }
            }
        }
        return out
    }

    /// Backup codes or a recovery key tucked into an item's notes.
    static func candidate(fromNotes notes: String, title: String, source: String) -> Candidate? {
        let text = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !Detector.isWalletSeed(text) else { return nil }
        let codes = RecoveryCodes.extract(text)
        if codes.count >= 4 {
            return Candidate(name: title, kind: .codes(codes), value: codes.joined(separator: "\n"), source: source, note: nil)
        }
        if let detection = Detector.detect(text), detection.kind == .recoveryKey {
            return Candidate(name: "\(title) recovery key", kind: .recoveryKey(.recoveryKey), value: text, source: source, note: nil)
        }
        return nil
    }
}

/// RFC 4180-ish CSV: quoted fields, doubled quotes, commas and newlines inside quotes.
public enum CSV {
    public static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        if chars.first == "\u{FEFF}" { chars.removeFirst() }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": quoted = true
                case ",": row.append(field); field = ""
                case "\n", "\r": row.append(field); rows.append(row); row = []; field = ""
                default: field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}

/// Just enough ZIP reading for an export file: finds one entry and inflates it in memory.
/// Stored and deflate entries only; no ZIP64 (exports are small).
public enum ZipReader {
    public static func file(named name: String, in data: Data) throws -> Data? {
        let bytes = [UInt8](data)
        func u16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        guard bytes.count >= 22 else { throw Importer.ImportError.unsupportedZip }

        // End of central directory: scan back from the end for its signature.
        var eocd = -1
        var o = bytes.count - 22
        while o >= max(0, bytes.count - 22 - 65_535) {
            if u32(o) == 0x0605_4B50 { eocd = o; break }
            o -= 1
        }
        guard eocd >= 0 else { throw Importer.ImportError.unsupportedZip }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)

        for _ in 0..<count {
            guard p + 46 <= bytes.count, u32(p) == 0x0201_4B50 else { throw Importer.ImportError.unsupportedZip }
            let method = u16(p + 10)
            let compressed = u32(p + 20)
            let size = u32(p + 24)
            let nameLength = u16(p + 28), extraLength = u16(p + 30), commentLength = u16(p + 32)
            let localHeader = u32(p + 42)
            let entryName = String(decoding: bytes[(p + 46)..<(p + 46 + nameLength)], as: UTF8.self)
            p += 46 + nameLength + extraLength + commentLength
            guard entryName == name || entryName.hasSuffix("/" + name) else { continue }

            guard localHeader + 30 <= bytes.count, u32(localHeader) == 0x0403_4B50 else { throw Importer.ImportError.unsupportedZip }
            let start = localHeader + 30 + u16(localHeader + 26) + u16(localHeader + 28)
            guard start + compressed <= bytes.count else { throw Importer.ImportError.unsupportedZip }
            let body = Array(bytes[start..<(start + compressed)])
            switch method {
            case 0:
                return Data(body)
            case 8:
                var out = [UInt8](repeating: 0, count: max(size, 1))
                let written = compression_decode_buffer(&out, out.count, body, body.count, nil, COMPRESSION_ZLIB)
                guard written == size else { throw Importer.ImportError.unsupportedZip }
                return Data(out.prefix(written))
            default:
                throw Importer.ImportError.unsupportedZip
            }
        }
        return nil
    }
}
