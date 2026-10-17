import AppKit
import LocalAuthentication
import SpikeCore
import SwiftUI

@main
struct SlinkySpikeApp: App {
    @StateObject private var model = SpikeModel()
    var body: some Scene {
        WindowGroup("Slinky Test") {
            SpikeView().environmentObject(model)
        }
        .defaultSize(width: 620, height: 520)
    }
}

final class SpikeModel: ObservableObject {
    @Published var log: [String] = []
    @Published var locked = true

    private let vault = EnclaveVault(service: "com.slinky.spike", vaultFile: SpikePaths.appVault)
    private var context = SpikeModel.freshContext()
    private let server = SocketServer(path: SpikePaths.socket)
    private let logFile = SpikePaths.supportDir.appendingPathComponent("app.log")
    private let queue = DispatchQueue(label: "slinky.spike.vault")

    init() {
        say("Launched (rebuild 2). Secure Enclave available: \(EnclaveVault.enclaveAvailable)")
        do {
            try server.start { [weak self] request, peer in self?.handle(request, peer) ?? "error: gone" }
            say("Listening on \(SpikePaths.socket.path)")
        } catch { say("Socket failed: \(error)") }

        DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.lock(reason: "screen locked")
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.lock(reason: "Mac going to sleep")
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.lock(reason: "display slept")
        }
    }

    static func freshContext() -> LAContext {
        let ctx = LAContext()
        ctx.localizedReason = "unlock the Slinky test vault"
        return ctx
    }

    // MARK: actions (buttons and socket share these)

    func run(_ action: String) -> String {
        queue.sync {
            do {
                switch action {
                case "create":
                    let key = try vault.createKey(context: context)
                    let fp = try vault.wrapNewVaultKey(to: key.publicKey)
                    return say("Created Secure Enclave key, stored its blob in the login keychain, wrapped a vault key (fingerprint \(fp)).")
                case "unwrap":
                    let start = Date()
                    let key = try vault.loadKey(context: context)
                    let result = try vault.unwrapVaultKey(with: key)
                    DispatchQueue.main.async { self.locked = false }
                    return say("Unwrapped vault key \(result.fingerprint) — \(result.matches ? "matches" : "DOES NOT MATCH") — in \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
                case "readblob":
                    let blob = try vault.loadBlob()
                    return say("Read the key blob from the login keychain (\(blob.count) bytes) with no prompt shown by the app.")
                case "lock":
                    lock(reason: "asked to lock")
                    return "locked"
                default:
                    return say("Unknown action \(action)")
                }
            } catch {
                return say("\(action) failed: \(error) [\(type(of: error))]")
            }
        }
    }

    func lock(reason: String) {
        queue.async {
            self.context.invalidate()
            self.context = SpikeModel.freshContext()
            DispatchQueue.main.async { self.locked = true }
            self.say("Locked (\(reason)). The next unwrap must ask again.")
        }
    }

    private func handle(_ request: String, _ peer: PeerInfo) -> String {
        say("Request \"\(request)\" from pid \(peer.pid): \(peer.chainText)")
        say("Signature: \(peer.signatureDetail)")
        guard peer.signatureOK else { return "refused: caller is not Slinky's own CLI (\(peer.signatureDetail))" }
        if request == "who" { return "ok · chain: \(peer.chainText) · signature: \(peer.signatureDetail)" }
        return run(request)
    }

    @discardableResult
    func say(_ line: String) -> String {
        let stamped = "\(Self.time.string(from: Date()))  \(line)"
        DispatchQueue.main.async { self.log.append(stamped) }
        if let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile(); handle.write(Data((stamped + "\n").utf8)); try? handle.close()
        } else {
            try? FileManager.default.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data((stamped + "\n").utf8).write(to: logFile)
        }
        return line
    }

    private static let time: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()
}

struct SpikeView: View {
    @EnvironmentObject var model: SpikeModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Slinky feasibility test").font(.headline)
                Spacer()
                Label(model.locked ? "Locked" : "Unlocked", systemImage: model.locked ? "lock.fill" : "lock.open.fill")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Create Key") { Task.detached { _ = model.run("create") } }
                Button("Unwrap") { Task.detached { _ = model.run("unwrap") } }
                Button("Read Blob") { Task.detached { _ = model.run("readblob") } }
                Button("Lock Now") { model.lock(reason: "button") }
            }
            List(model.log, id: \.self) { Text($0).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
        }
        .padding()
    }
}
