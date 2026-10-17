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
            var line = rawLine.trimmingCharacters(in: .whitespaces)
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

    /// Names only, for .env.example files.
    public static func names(_ text: String) -> [String] { parse(text).map(\.name) }

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
