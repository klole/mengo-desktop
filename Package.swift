// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ScreenpipeMenu",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "ScreenpipeMenu",
            path: "Sources/ScreenpipeMenu"
        ),
        .testTarget(
            name: "ScreenpipeMenuTests",
            dependencies: ["ScreenpipeMenu"],
            path: "Tests/ScreenpipeMenuTests"
        ),
        .executableTarget(
            name: "ScreenpipeFlow",
            path: "Sources/ScreenpipeFlow",
            resources: [
                .copy("../../Resources/synthesis-prompt.md")
            ]
        ),
        .testTarget(
            name: "ScreenpipeFlowTests",
            dependencies: ["ScreenpipeFlow"],
            path: "Tests/ScreenpipeFlowTests"
        ),
        .executableTarget(
            name: "MengoDesktop",
            path: "Sources/MengoDesktop"
        )
    ]
)
