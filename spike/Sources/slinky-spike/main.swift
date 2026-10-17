import Foundation
import LocalAuthentication
import SpikeCore

// slinky-spike: the CLI half of the feasibility test.
//   create-own / unwrap-own  — its own Secure Enclave key, to see Touch ID from Terminal (check 2)
//   app <who|create|unwrap|readblob|lock> — ask the app over the socket (checks 1, 3, 4, 5, 7)
//   chain — print this process's own parent chain

let args = Array(CommandLine.arguments.dropFirst())
let vault = EnclaveVault(service: "com.slinky.spike.cli", vaultFile: SpikePaths.cliVault)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("slinky-spike: \(message)\n".utf8))
    exit(1)
}

switch args.first {
case "create-own":
    let ctx = LAContext(); ctx.localizedReason = "create the Slinky test key for Terminal"
    do {
        let key = try vault.createKey(context: ctx)
        let fp = try vault.wrapNewVaultKey(to: key.publicKey)
        print("created CLI Secure Enclave key; wrapped vault key \(fp)")
    } catch { fail("create-own failed: \(error) [\(type(of: error))]") }

case "unwrap-own":
    let ctx = LAContext(); ctx.localizedReason = "unlock the Slinky test vault from Terminal"
    do {
        let start = Date()
        let r = try vault.unwrapVaultKey(with: try vault.loadKey(context: ctx))
        print("unwrapped \(r.fingerprint) — \(r.matches ? "matches" : "DOES NOT MATCH") — \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
    } catch { fail("unwrap-own failed: \(error) [\(type(of: error))]") }

case "app":
    guard args.count >= 2 else { fail("usage: slinky-spike app <who|create|unwrap|readblob|lock>") }
    do { print(try SocketClient.send(args[1], to: SpikePaths.socket)) }
    catch { fail("could not reach the app: \(error). Is SlinkySpike.app running?") }

case "chain":
    print(ProcessChain.walk(from: getpid()).map(\.name).reversed().joined(separator: " › "))

default:
    print("usage: slinky-spike <create-own | unwrap-own | app <who|create|unwrap|readblob|lock> | chain>")
}
