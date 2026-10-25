// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Roger",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Roger", targets: ["Roger"])],
    targets: [
        .executableTarget(name: "Roger"),
        .testTarget(name: "RogerTests", dependencies: ["Roger"])
    ]
)
