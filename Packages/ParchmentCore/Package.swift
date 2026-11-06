// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ParchmentCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ParchmentCore", targets: ["ParchmentCore"])
    ],
    targets: [
        .target(name: "ParchmentCore"),
        .testTarget(name: "ParchmentCoreTests", dependencies: ["ParchmentCore"])
    ]
)
