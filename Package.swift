// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LuLuSidekick",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "SidekickCore", path: "Sources/SidekickCore"),
        .executableTarget(name: "LuLuSidekick", dependencies: ["SidekickCore"], path: "Sources/LuLuSidekick"),
        .testTarget(name: "SidekickCoreTests", dependencies: ["SidekickCore"], path: "Tests"),
    ],
    swiftLanguageVersions: [.v5]
)
