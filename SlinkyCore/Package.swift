// swift-tools-version: 6.2
// SlinkyCore: everything Slinky knows that isn't UI. Apple frameworks only, no dependencies.
import PackageDescription

let package = Package(
    name: "SlinkyCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SlinkyCoreShared", targets: ["SlinkyCoreShared"]),
        .library(name: "SlinkyCoreVault", targets: ["SlinkyCoreVault"]),
        .executable(name: "slinky", targets: ["SlinkyCLI"]),
    ],
    targets: [
        // Models, paste detection, .env parsing. No crypto, no I/O beyond pure functions.
        .target(name: "SlinkyCoreShared"),
        // The encrypted vault: Secure Enclave key wrapping, Recovery Key, vault file format.
        .target(name: "SlinkyCoreVault", dependencies: ["SlinkyCoreShared"]),
        // The `slinky` command-line tool. Agent features land in a later milestone.
        .executableTarget(name: "SlinkyCLI", dependencies: ["SlinkyCoreShared"]),
        .testTarget(name: "SlinkyCoreTests", dependencies: ["SlinkyCoreShared", "SlinkyCoreVault"]),
    ]
)
