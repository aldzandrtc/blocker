// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Blocker",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Blocker",
            path: "Blocker",
            exclude: ["Resources", "ChromeExt"]
        )
    ]
)
