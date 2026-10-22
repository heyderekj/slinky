import Foundation

public struct DotEnvLine: Equatable, Hashable, Sendable {
    public var name: String
    public var value: String
    /// The nearest `# comment` above this line, used as a group heading ("# Payments").
    public var group: String?

    public init(name: String, value: String, group: String? = nil) {
        self.name = name
        self.value = value
        self.group = group
    }

    /// Values that ship to the browser anyway are plain config, not secrets.
    public var isPlain: Bool { DotEnv.isPlainName(name) }
}

public enum DotEnv {
    /// Parses .env text. Handles `export`, single and double quotes, inline `# comments`, and blank lines.
    public static func parse(_ text: String) -> [DotEnvLine] {
        var out: [DotEnvLine] = []
        var group: String?
        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            var line = cleaned(String(rawLine))
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                let heading = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                group = heading.isEmpty ? group : heading
                continue
            }
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let name = line[..<eq].trimmingCharacters(in: .whitespaces)
            guard name.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else { continue }
            out.append(DotEnvLine(name: name, value: unquote(String(line[line.index(after: eq)...])), group: group))
        }
        return out
    }

    /// Names only, for .env.example files. Each name once, in order.
    public static func names(_ text: String) -> [String] {
        var seen = Set<String>()
        return parse(text).map(\.name).filter { seen.insert($0).inserted }
    }

    /// Zero-width spaces, joiners and byte-order marks, removed by Unicode scalar (a joiner merges into the
    /// character before it, so filtering characters misses it).
    public static func withoutInvisibles(_ text: String) -> String {
        let invisible: Set<UInt32> = [0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF]
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.unicodeScalars.filter { !invisible.contains($0.value) })
        return String(scalars)
    }

    /// What people actually paste: a line copied from a chat or a doc can carry invisible characters, a shell
    /// prompt, or the backticks and quotes it was shown in. A variable name can't start with any of those.
    static func cleaned(_ raw: String) -> String {
        var line = withoutInvisibles(raw).trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("$ ") { line = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        while let first = line.first, ["`", "\"", "'", "“", "‘"].contains(first), line.count > 2 {
            let closing: Character = first == "“" ? "”" : first == "‘" ? "’" : first
            guard line.last == closing else { break }
            line = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return line
    }

    public static func isPlainName(_ name: String) -> Bool {
        let publicPrefixes = ["NEXT_PUBLIC_", "VITE_", "PUBLIC_", "EXPO_PUBLIC_", "NUXT_PUBLIC_", "GATSBY_", "REACT_APP_"]
        return publicPrefixes.contains { name.hasPrefix($0) }
    }

    /// Renders lines back to .env text (used for "Copy as .env" on purpose, never written to disk by Slinky).
    public static func render(_ lines: [(String, String)]) -> String {
        lines.map { name, value in
            let needsQuotes = value.contains { $0 == " " || $0 == "#" || $0 == "\"" || $0 == "'" }
            let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
            return "\(name)=" + (needsQuotes ? "\"\(escaped)\"" : value)
        }.joined(separator: "\n")
    }

    private static func unquote(_ raw: String) -> String {
        let v = raw.trimmingCharacters(in: .whitespaces)
        if let first = v.first, first == "\"" || first == "'" {
            let body = v.dropFirst()
            if let close = body.firstIndex(of: first) {
                let inner = String(body[..<close])
                return first == "\"" ? inner.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\\"", with: "\"") : inner
            }
            return String(body)
        }
        // Unquoted: an inline comment starts at " #".
        if let hash = v.range(of: " #") { return String(v[..<hash.lowerBound]).trimmingCharacters(in: .whitespaces) }
        return v
    }
}
