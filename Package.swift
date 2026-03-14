// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LanScanner",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "LanScanner",
            path: "Sources/LanScanner",
            exclude: ["Info.plist", "Assets.xcassets"]
        )
    ]
)
