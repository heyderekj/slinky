import Foundation
import SlinkyCoreShared

/// `slinky notarize-profile NAME --item "App Store Connect key"`: saves a notarytool keychain profile from an App
/// Store Connect API key kept in Slinky. The .p8 is written to a private temp file (0600) only for the moment
/// notarytool reads it, then deleted. The key ID and issuer go in arguments; they aren't secret.
extension AppModel {
    func notarizeProfile(_ request: Broker.Request, peer: Peer) async -> Broker.Response {
        guard !peer.isAgent else { return .fail("Agents can't save notarization profiles.") }
        guard let profile = request.name, profile.range(of: #"^[A-Za-z0-9._-]{1,64}$"#, options: .regularExpression) != nil else {
            return .fail("Give a profile name like slinky-notary.")
        }
        guard await approve(reason: "save a notarytool profile “\(profile)” from an App Store Connect key in Slinky") else {
            return .fail("Not allowed.")
        }
        let keys = document.secretFiles.filter { $0.kind == .appStoreConnectKey }
        let chosen = request.text.flatMap { name in keys.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } } ?? (keys.count == 1 ? keys.first : nil)
        guard let file = chosen else {
            return .fail(keys.isEmpty ? "Slinky has no App Store Connect API key. Add the .p8 file in Slinky first."
                                      : "Slinky has more than one App Store Connect key. Pass --item with its name.")
        }
        guard let keyID = file.fields["Key ID"] ?? SecretFile.keyID(fromFilename: file.filename), let issuer = file.fields["Issuer ID"] else {
            return .fail("Add the Key ID and Issuer ID to \(file.name) in Slinky first.")
        }
        let output = await Task.detached { () -> (Int32, String) in
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("slinky-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: dir) }
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let path = dir.appendingPathComponent("AuthKey_\(keyID).p8")
                FileManager.default.createFile(atPath: path.path, contents: file.data, attributes: [.posixPermissions: 0o600])
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
                process.arguments = ["notarytool", "store-credentials", profile, "--key", path.path, "--key-id", keyID, "--issuer", issuer]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                try process.run()
                process.waitUntilExit()
                let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                return (process.terminationStatus, text)
            } catch {
                return (1, "Couldn't run notarytool: \(error.localizedDescription)")
            }
        }.value
        record(ActivityEntry(action: .notarized, names: [file.name], actor: peer.display, detail: "notarytool profile \(profile)"))
        var r = Broker.Response(ok: output.0 == 0)
        r.message = output.0 == 0 ? "Saved the notarytool profile “\(profile)”. Use: xcrun notarytool submit … --keychain-profile \(profile)" : output.1
        return r
    }
}
