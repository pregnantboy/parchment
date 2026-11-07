// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ParchmentCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ParchmentCore", targets: ["ParchmentCore"]),
        .library(name: "ParchmentAgent", targets: ["ParchmentAgent"])
    ],
    targets: [
        // Markdown parsing and editing. Foundation-free.
        .target(name: "ParchmentCore"),
        // Following Claude Code sessions through hook events. Uses Foundation; builds on Linux too.
        .target(name: "ParchmentAgent", dependencies: ["ParchmentCore"]),
        .testTarget(name: "ParchmentCoreTests", dependencies: ["ParchmentCore"]),
        .testTarget(name: "ParchmentAgentTests", dependencies: ["ParchmentAgent", "ParchmentCore"])
    ]
)
