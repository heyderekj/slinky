import Foundation

/// Reading and writing a file that a sync service (iCloud Drive, Dropbox, a NAS) also moves: through
/// NSFileCoordinator, so neither side sees half a file, and asking iCloud for files it keeps only as placeholders.
/// Used by the vault's sync copy and by shared projects.
enum CoordinatedFile {
    static func read(_ url: URL, presenter: NSFilePresenter?) -> Data? {
        downloadIfNeeded(url)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var out: Data?
        var error: NSError?
        NSFileCoordinator(filePresenter: presenter).coordinate(readingItemAt: url, options: [], error: &error) { url in
            out = try? Data(contentsOf: url)
        }
        return out
    }

    /// Atomic, 0600.
    static func write(_ data: Data, to url: URL, presenter: NSFilePresenter?) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var failure: Error?
        var error: NSError?
        NSFileCoordinator(filePresenter: presenter).coordinate(writingItemAt: url, options: .forReplacing, error: &error) { url in
            do {
                try data.write(to: url, options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch { failure = error }
        }
        if let failure { throw failure }
        if let error { throw error }
    }

    /// iCloud Drive may keep only a placeholder until asked.
    static func downloadIfNeeded(_ url: URL) {
        guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
              values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus != .current else { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    /// "harvous (conflicted copy).slinkyproject", "harvous 2.slinkyproject": what Dropbox and iCloud leave when two
    /// Macs write at once. Files next to `url` whose names start like it and end in the same extension.
    static func conflictedCopies(of url: URL) -> [URL] {
        let dir = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.filter { $0 != url.lastPathComponent && $0.hasPrefix(stem) && ($0 as NSString).pathExtension == ext }
            .map { dir.appendingPathComponent($0) }
    }
}
