// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "XcodeBuildStatus", platforms: [.macOS(.v13)], products: [
    .executable(name: "xcode-build-status", targets: ["XcodeBuildStatus"])
], targets: [
    .target(name: "BuildStatusCore"),
    .executableTarget(name: "XcodeBuildStatus", dependencies: ["BuildStatusCore"], linkerSettings: [.linkedLibrary("z")]),
    .testTarget(name: "BuildStatusCoreTests", dependencies: ["BuildStatusCore"]),
    .testTarget(name: "RuntimeTests", dependencies: ["XcodeBuildStatus"])
])
