// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DozerCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "DozerCore", targets: ["DozerCore"])],
    targets: [
        .target(name: "DozerCore", path: "DozerCore"),
        .testTarget(name: "DozerTests", dependencies: ["DozerCore"], path: "Tests/DozerTests")
    ]
)
