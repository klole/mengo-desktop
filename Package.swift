// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ScreenpipeMenu",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "ScreenpipeMenu",
            path: "Sources/ScreenpipeMenu"
        )
    ]
)
