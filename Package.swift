// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Roger",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Roger", targets: ["Roger"]),
        // Development only: retakes the README screenshots. Never shipped.
        .executable(name: "roger-shot", targets: ["RogerShot"])
    ],
    targets: [
        .target(name: "RogerCore"),
        .executableTarget(name: "Roger", dependencies: ["RogerCore"]),
        .executableTarget(name: "RogerShot", dependencies: ["RogerCore"]),
        .testTarget(name: "RogerTests", dependencies: ["RogerCore"])
    ]
)
