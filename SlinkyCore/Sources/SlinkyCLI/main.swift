import Foundation
import SlinkyCoreShared

// `slinky` — placeholder until the agent milestone (run, ls, check, import, mcp).
// For now it can check what a value looks like, without storing anything.

let args = Array(CommandLine.arguments.dropFirst())

switch args.first {
case "detect":
    let text = args.count > 1 ? args.dropFirst().joined(separator: " ") : String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    if let d = Detector.detect(text) {
        print("\(d.label) → \(d.destination.title)")
    } else {
        print("Nothing to look at.")
    }
case "--version", "version":
    print("slinky 0.1.0 (early)")
default:
    print("""
    slinky 0.1.0 (early)

    usage:
      slinky detect <value>   Say what a value looks like and where Slinky would put it.

    Coming next: slinky run, ls, check, import, mcp.
    """)
}
