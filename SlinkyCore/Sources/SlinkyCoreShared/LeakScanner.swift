import Foundation

/// Finds exact copies of saved values in text or files. Slinky knows the real values, so there's no guessing:
/// a match is the value itself. Runs in memory, in the app, and reports names and places only.
public enum LeakScanner {
    public struct Secret: Sendable, Hashable {
        public let name: String
        public let value: String
        public init(name: String, value: String) { self.name = name; self.value = value }
    }

    /// Shorter values would match ordinary text by chance.
    public static let minLength = 8

    /// Names of the secrets whose values appear in `text`, in the order given, without repeats.
    public static func matches(in text: String, secrets: [Secret]) -> [String] {
        matches(in: Data(text.utf8), secrets: secrets)
    }

    public static func matches(in data: Data, secrets: [Secret]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for s in searchable(secrets) where !seen.contains(s.name) {
            if data.range(of: Data(s.value.utf8)) != nil {
                seen.insert(s.name)
                out.append(s.name)
            }
        }
        return out
    }

    /// Line numbers (1-based) in `text` where `value` appears.
    public static func lines(of value: String, in text: String) -> [Int] {
        var out: [Int] = []
        for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() where line.contains(value) {
            out.append(i + 1)
        }
        return out
    }

    /// Text with every line containing one of the values removed (for cleaning shell history).
    public static func removingLines(containing values: [String], from text: String) -> (text: String, removed: Int) {
        var removed = 0
        let kept = text.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            let hit = values.contains { !$0.isEmpty && line.contains($0) }
            if hit { removed += 1 }
            return !hit
        }
        return (kept.joined(separator: "\n"), removed)
    }

    static func searchable(_ secrets: [Secret]) -> [Secret] {
        secrets.compactMap { s in
            let v = s.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return v.count >= minLength ? Secret(name: s.name, value: v) : nil
        }
    }
}
