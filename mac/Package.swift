// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hearth",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Hearth",
            path: "Sources/Hearth",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HearthTests",
            dependencies: ["Hearth"],
            path: "Tests/HearthTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
