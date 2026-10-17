// swift-tools-version: 6.2
// Throwaway feasibility test for Slinky: Secure Enclave + legacy keychain + socket peer checks.
import PackageDescription

let package = Package(
    name: "SlinkySpike",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "SpikeCore"),
        .executableTarget(name: "SlinkySpike", dependencies: ["SpikeCore"]),
        .executableTarget(name: "slinky-spike", dependencies: ["SpikeCore"]),
    ],
    swiftLanguageModes: [.v5]
)
