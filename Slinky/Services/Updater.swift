import AppKit
import Security

/// Update checks and in-place installs, like Dinky's: asks GitHub for the latest release (once a day,
/// or when you choose Check for Updates…), and installs it over this copy so there's no second
/// Open Anyway. The only thing sent is the request itself. No data about you or your vault.
///
/// Slinky holds secrets, so one step Dinky doesn't need: before installing, the downloaded app must be
/// signed by Testament Made's team as com.slinky.app. Anything else is refused.
@MainActor
@Observable
final class Updater {
    static let shared = Updater()

    enum InstallState: Equatable { case idle, downloading, installing, failed(String) }
    enum CheckResult { case updateAvailable, upToDate, failed }

    private(set) var availableVersion: String?
    private(set) var releaseURL: URL?
    private(set) var downloadURL: URL?
    private(set) var isChecking = false
    private(set) var installState: InstallState = .idle

    private let apiURL = URL(string: "https://api.github.com/repos/heyderekj/slinky/releases/latest")!
    /// Only an app signed by this team, with this identifier, may replace Slinky.
    private let requirement = #"identifier "com.slinky.app" and anchor apple generic and certificate leaf[subject.OU] = "B3U6BXA8KP""#

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
        let assets: [Asset]
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
    }

    var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0" }

    /// The banner shows unless the person dismissed this exact version.
    var shouldShowBanner: Bool {
        guard let v = availableVersion else { return false }
        return UserDefaults.standard.string(forKey: "dismissedUpdateVersion") != v
    }

    func checkOnLaunch() {
        guard Preferences.shared.checkForUpdates else { return }
        let last = UserDefaults.standard.double(forKey: "lastUpdateCheck")
        guard Date.now.timeIntervalSince1970 - last > 86_400 else { return }
        Task { await check() }
    }

    /// Check for Updates… in the app menu: always asks, and always answers.
    func checkManually() {
        Task {
            let result = await check()
            let alert = NSAlert()
            switch result {
            case .updateAvailable:
                alert.messageText = "Slinky \(availableVersion ?? "") is available."
                alert.informativeText = "You're on \(currentVersion). Install it now? Slinky reopens when it's done, still locked."
                alert.addButton(withTitle: "Install")
                alert.addButton(withTitle: "Not Now")
                if alert.runModal() == .alertFirstButtonReturn { await install() }
            case .upToDate:
                alert.messageText = "All caught up."
                alert.informativeText = "You're on Slinky \(currentVersion), the latest."
                alert.addButton(withTitle: "Nice")
                alert.runModal()
            case .failed:
                alert.messageText = "Couldn't phone home."
                alert.informativeText = "Probably the internet. Try again in a sec?"
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    func dismissBanner() {
        if let v = availableVersion { UserDefaults.standard.set(v, forKey: "dismissedUpdateVersion") }
        availableVersion = nil
    }

    @discardableResult
    func check() async -> CheckResult {
        isChecking = true
        defer { isChecking = false }
        var request = URLRequest(url: apiURL, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Slinky", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: data) else { return .failed }
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "lastUpdateCheck")

        let remote = Self.stripV(release.tag_name)
        guard Self.isNewer(remote, than: currentVersion) else {
            availableVersion = nil
            return .upToDate
        }
        availableVersion = remote
        releaseURL = URL(string: release.html_url)
        downloadURL = release.assets.first { $0.name.lowercased().hasSuffix(".zip") }.flatMap { URL(string: $0.browser_download_url) }
        return .updateAvailable
    }

    /// Downloads the zip, unpacks it, checks the signature, then swaps the app after Slinky quits.
    func install() async {
        guard installState != .downloading, installState != .installing else { return }
        guard let downloadURL else {
            installState = .failed("This release doesn't have a download yet. Try again in a minute.")
            return
        }
        installState = .downloading
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("slinky-update-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let (downloaded, _) = try await URLSession.shared.download(from: downloadURL)
            let zip = work.appendingPathComponent("Slinky.zip")
            try fm.moveItem(at: downloaded, to: zip)

            installState = .installing
            try await Self.run("/usr/bin/ditto", ["-xk", zip.path, work.appendingPathComponent("unpacked").path])
            let staged = work.appendingPathComponent("unpacked/Slinky.app")
            guard fm.fileExists(atPath: staged.path) else { throw UpdateError.missingApp }
            guard isTrusted(staged) else { throw UpdateError.untrusted }
            guard runsHere(staged) else { throw UpdateError.wrongMac }

            try replaceAfterQuit(staged: staged, destination: Bundle.main.bundleURL, cleanup: work)
            // Lock first, so nothing secret is in memory while the app swaps.
            AppModel.shared.lock(reason: .manual)
            Thread.detachNewThread {
                Thread.sleep(forTimeInterval: 4)
                exit(0)
            }
            NSApp.terminate(nil)
        } catch {
            try? fm.removeItem(at: work)
            installState = .failed((error as? UpdateError)?.message ?? "The update didn't install. Download it from GitHub instead.")
        }
    }

    /// Valid signature, our team, our identifier.
    /// Slinky is Apple silicon only from 1.0.1. Never install a build this Mac can't open.
    private func runsHere(_ app: URL) -> Bool {
        guard let archs = Bundle(url: app)?.executableArchitectures?.map(\.intValue) else { return false }
        #if arch(arm64)
        return archs.contains(NSBundleExecutableArchitectureARM64)
        #else
        return archs.contains(NSBundleExecutableArchitectureX86_64)
        #endif
    }

    private func isTrusted(_ app: URL) -> Bool {
        var code: SecStaticCode?
        var req: SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), req) == errSecSuccess
    }

    /// A small script waits for Slinky to quit, swaps the bundle, clears quarantine and reopens it.
    private func replaceAfterQuit(staged: URL, destination: URL, cleanup: URL) throws {
        func q(_ path: String) -> String { "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = [
            "#!/bin/bash",
            "deadline=$(( $(date +%s) + 10 ))",
            "while kill -0 \(pid) 2>/dev/null && [ $(date +%s) -lt $deadline ]; do sleep 0.2; done",
            "rm -rf \(q(destination.path)) || exit 1",
            "/usr/bin/ditto \(q(staged.path)) \(q(destination.path)) || exit 1",
            "/usr/bin/xattr -rd com.apple.quarantine \(q(destination.path)) 2>/dev/null || true",
            "rm -rf \(q(cleanup.path))",
            "/usr/bin/open -n \(q(destination.path))",
        ].joined(separator: "\n")
        let url = cleanup.appendingPathComponent("install.sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [url.path]
        try process.run()
    }

    private enum UpdateError: Error {
        case missingApp, untrusted, wrongMac
        var message: String {
            switch self {
            case .missingApp: "The download didn't contain Slinky. Download it from GitHub instead."
            case .untrusted: "The download isn't signed by Slinky's developer, so it wasn't installed."
            case .wrongMac: "This version of Slinky needs a Mac with Apple silicon, so it wasn't installed."
            }
        }
    }

    private static func run(_ tool: String, _ args: [String]) async throws {
        try await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            try p.run()
            p.waitUntilExit()
            if p.terminationStatus != 0 { throw UpdateError.missingApp }
        }.value
    }

    static func stripV(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("v") || t.hasPrefix("V") ? String(t.dropFirst()) : t
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
