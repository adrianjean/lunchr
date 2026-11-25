// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "lunchr",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LunchrCore"),
        .executableTarget(name: "Lunchr", dependencies: ["LunchrCore"]),
        .testTarget(name: "LunchrCoreTests", dependencies: ["LunchrCore"]),
    ]
)
