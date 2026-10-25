// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CopyOver",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CopyOver", targets: ["CopyOver"])],
    targets: [
        .executableTarget(name: "CopyOver"),
        .testTarget(name: "CopyOverTests", dependencies: ["CopyOver"])
    ]
)
