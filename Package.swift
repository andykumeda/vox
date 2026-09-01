// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vox",
    platforms: [
        .macOS(.v13),
        .iOS(.v18),
    ],
    products: [
        .library(name: "VoxCore", targets: ["VoxCore"]),
        .executable(name: "vox", targets: ["vox"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "VoxCore",
            path: "Sources/VoxCore",
            exclude: ["Package.swift"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "vox",
            dependencies: [
                "VoxCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/vox",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "voxTests",
            dependencies: ["vox", "VoxCore"],
            path: "Tests/voxTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "VoxCoreTests",
            dependencies: ["VoxCore"],
            path: "Tests/VoxCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
