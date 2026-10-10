// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoxCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v18),
    ],
    products: [
        .library(name: "VoxCore", targets: ["VoxCore"]),
    ],
    targets: [
        .target(
            name: "VoxCore",
            path: ".",
            exclude: ["Package.swift"],
            resources: [.process("Configuration/service-defaults.json")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
