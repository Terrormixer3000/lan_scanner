// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LanScanner",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "LanScanner",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/LanScanner",
            exclude: ["Info.plist", "Assets.xcassets", "AppIcon.icns"]
        )
    ]
)
