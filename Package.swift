// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacNotch",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacNotch", targets: ["MacNotch"])
    ],
    targets: [
        // Pure Foundation logic: models, persistence, geometry, parsing, state machine.
        .target(name: "NotchCore", path: "Sources/NotchCore"),
        // AppKit + SwiftUI: the island panel, widgets, services and settings.
        .target(name: "NotchUI", dependencies: ["NotchCore"], path: "Sources/NotchUI"),
        // Thin launcher.
        .executableTarget(name: "MacNotch", dependencies: ["NotchUI"], path: "Sources/MacNotch"),
        .testTarget(name: "NotchCoreTests", dependencies: ["NotchCore"], path: "Tests/NotchCoreTests"),
        .testTarget(name: "NotchUITests", dependencies: ["NotchUI", "NotchCore"], path: "Tests/NotchUITests")
    ]
)
