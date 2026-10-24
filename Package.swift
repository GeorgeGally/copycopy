// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CopyCopy",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CopyCopy", targets: ["CopyCopy"])],
    targets: [
        .executableTarget(name: "CopyCopy"),
        .testTarget(name: "CopyCopyTests", dependencies: ["CopyCopy"])
    ]
)
