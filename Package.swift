// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vox",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "vox",
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
