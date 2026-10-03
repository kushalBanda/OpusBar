// swift-tools-version:5.10
import PackageDescription

let strict: [SwiftSetting] = [.enableExperimentalFeature("StrictConcurrency")]

let package = Package(
    name: "OpusBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OpusBar", targets: ["OpusBar"]),
        .executable(name: "opusbar-hook", targets: ["opusbar-hook"]),
    ],
    targets: [
        // Shared by the hook binary and the app: wire format, socket client, paths.
        .target(name: "OpusBarWire", swiftSettings: strict),
        .executableTarget(name: "opusbar-hook", dependencies: ["OpusBarWire"], swiftSettings: strict),
        .target(name: "OpusBarCore", dependencies: ["OpusBarWire"], swiftSettings: strict),
        .executableTarget(
            name: "OpusBar",
            dependencies: ["OpusBarCore", "OpusBarWire"],
            resources: [
                .copy("Resources/Coats"), .copy("Resources/AgentLogos"), .copy("Resources/Catppuccineko-LICENSE.txt"),
                .copy("Resources/spicetify-oneko-LICENSE.txt"), .copy("Resources/0xdhrv-oneko-LICENSE.txt"),
                .copy("Resources/InterVariable.ttf"), .copy("Resources/Inter-LICENSE.txt"),
                .copy("Resources/PixelifySans.ttf"), .copy("Resources/PixelifySans-LICENSE.txt"),
                .copy("Resources/usage-prices.json"),
            ]
        ),
        .testTarget(name: "OpusBarWireTests", dependencies: ["OpusBarWire"]),
        .testTarget(name: "OpusBarCoreTests", dependencies: ["OpusBarCore", "OpusBarWire"]),
    ]
)
