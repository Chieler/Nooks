// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Nooks",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "SpaceBridge", publicHeadersPath: "include", linkerSettings: [.linkedFramework("ApplicationServices")]),
        .executableTarget(name: "Nooks", dependencies: ["SpaceBridge"]),
        .testTarget(name: "NooksTests", dependencies: ["Nooks"])
    ]
)
