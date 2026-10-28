// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LibreReplace",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LibreReplaceCore", targets: ["LibreReplaceCore"]),
        .executable(name: "libreplace", targets: ["LibreReplaceCLI"])
    ],
    targets: [
        .target(name: "LibreReplaceCore"),
        .executableTarget(name: "LibreReplaceCLI", dependencies: ["LibreReplaceCore"]),
        .testTarget(name: "LibreReplaceCoreTests", dependencies: ["LibreReplaceCore"])
    ]
)
