import Foundation

/// The web address saved with an item (where a key was made, the account page, a dashboard).
public enum Links {
    /// "dash.cloudflare.com" → "https://dash.cloudflare.com". Only web addresses: anything that isn't
    /// http(s) with a real host is refused (nil), and http is upgraded to https.
    public static func normalized(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if text.lowercased().hasPrefix("http://") { text = "https://" + text.dropFirst(7) }
        if !text.lowercased().hasPrefix("https://") {
            guard !text.contains("://") else { return nil }
            text = "https://" + text
        }
        guard let url = URL(string: text), url.scheme?.lowercased() == "https",
              let host = url.host, host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else { return nil }
        return url.absoluteString
    }

    /// "https://dash.cloudflare.com/abc" → "dash.cloudflare.com".
    public static func host(of link: String?) -> String? {
        guard let link, let host = URL(string: link)?.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
