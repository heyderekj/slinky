import AppKit
import SlinkyCoreShared

/// Fetches a website's own icon, only when the person turns it on in Settings or asks for one item.
/// It goes straight to that website over https (no icon service in between), with no cookies, no cache
/// and nothing else attached: the site sees a request for its home page and its icon. The result is a small
/// PNG kept inside the encrypted vault, so which sites you use never sits on disk in the clear.
enum WebsiteIcons {
    enum Failure: Error { case badDomain, notFound, tooBig }

    static let maxBytes = 512 * 1024
    static let pixelSize = 64

    /// "github.com" → a 64px PNG.
    static func fetch(domain raw: String) async throws -> Data {
        let domain = raw.lowercased()
        guard domain.range(of: #"^[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$"#, options: .regularExpression) != nil,
              let home = URL(string: "https://\(domain)/") else { throw Failure.badDomain }
        var candidates: [URL] = []
        if let (html, finalURL) = try? await get(home), let text = String(data: html, encoding: .utf8) ?? String(data: html, encoding: .isoLatin1) {
            candidates = iconLinks(in: text, base: finalURL)
        }
        candidates.append(URL(string: "https://\(domain)/apple-touch-icon.png")!)
        candidates.append(URL(string: "https://\(domain)/favicon.ico")!)
        for url in candidates {
            guard let (data, _) = try? await get(url), let png = shrink(data) else { continue }
            return png
        }
        throw Failure.notFound
    }

    // MARK: Network

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// Refuses anything but https, including redirects to plain http.
    private final class HTTPSOnly: NSObject, URLSessionTaskDelegate, Sendable {
        nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(request.url?.scheme == "https" ? request : nil)
        }
    }

    private static func get(_ url: URL) async throws -> (Data, URL) {
        guard url.scheme == "https" else { throw Failure.badDomain }
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        let (bytes, response) = try await session.bytes(for: request, delegate: HTTPSOnly())
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw Failure.notFound }
        if http.expectedContentLength > maxBytes { throw Failure.tooBig }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > maxBytes { throw Failure.tooBig }
        }
        return (data, response.url ?? url)
    }

    // MARK: Parsing

    /// The page's own icons, best first: apple-touch-icon, then the largest "icon".
    static func iconLinks(in html: String, base: URL) -> [URL] {
        guard let tagRE = try? NSRegularExpression(pattern: #"<link\b[^>]*>"#, options: .caseInsensitive) else { return [] }
        let ns = html as NSString
        var found: [(URL, Int)] = []
        for match in tagRE.matches(in: html, range: NSRange(location: 0, length: min(ns.length, 200_000))) {
            let tag = ns.substring(with: match.range)
            guard let rel = attribute("rel", in: tag)?.lowercased(), let href = attribute("href", in: tag) else { continue }
            let words = Set(rel.split(separator: " ").map(String.init))
            let score: Int
            if words.contains("apple-touch-icon") || words.contains("apple-touch-icon-precomposed") {
                score = 1000
            } else if words.contains("icon") {
                let size = attribute("sizes", in: tag).flatMap { Int($0.lowercased().split(separator: "x").first ?? "") } ?? 16
                score = min(size, 512)
            } else {
                continue
            }
            let decoded = href.replacingOccurrences(of: "&amp;", with: "&")
            guard let url = URL(string: decoded, relativeTo: base)?.absoluteURL, url.scheme == "https" else { continue }
            found.append((url, score))
        }
        return found.sorted { $0.1 > $1.1 }.map(\.0)
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = #"\b"# + name + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for i in 1...3 {
            if let r = Range(m.range(at: i), in: tag) { return String(tag[r]) }
        }
        return nil
    }

    /// Any image macOS can read, redrawn as a 64px PNG. Too small or unreadable → nil.
    static func shrink(_ data: Data) -> Data? {
        guard let image = NSImage(data: data), image.size.width >= 16, image.size.height >= 16,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelSize, pixelsHigh: pixelSize,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
