// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CrazyNotch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CrazyNotch",
            path: "Sources/CrazyNotch",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
