import Foundation
import SlinkyCoreShared

// A development helper. The real `slinky` command is the app's own binary (Slinky/Agents/Command.swift), installed
// from Slinky › Settings › Command Line & Agents, so the app can check by code signature that it's really Slinky.

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

    The full command (run, env, xcconfig, ls, check, guard, hook, mcp) comes with the app:
    Slinky › Settings › Command Line & Agents › Install.
    """)
}
