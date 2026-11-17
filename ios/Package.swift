// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TapLateCore",
    platforms: [.iOS("27.0"), .macOS(.v14)],
    products: [.library(name: "TapLateCore", targets: ["TapLateCore"])],
    targets: [
        .target(name: "TapLateCore"),
        .testTarget(name: "TapLateCoreTests", dependencies: ["TapLateCore"])
    ]
)
