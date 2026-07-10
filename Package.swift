// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MengoDesktop",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "MengoDesktop",
            path: "Sources/MengoDesktop"
        ),
        .testTarget(
            name: "MengoDesktopTests",
            dependencies: ["MengoDesktop"],
            path: "Tests/MengoDesktopTests",
            exclude: ["Fixtures"]
        )
    ]
)
