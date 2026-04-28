// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vox",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "vox",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/vox",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "voxTests",
            dependencies: ["vox"],
            path: "Tests/voxTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
