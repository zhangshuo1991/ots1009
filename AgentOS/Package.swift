// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AgentOS",
    platforms: [
        .macOS(.v15),
    ],
    targets: [
        // -- GhosttyKit ------------------------------------------------
        .binaryTarget(name: "GhosttyKit", path: "Frameworks/GhosttyKit.xcframework"),

        .executableTarget(
            name: "AgentOS",
            dependencies: ["GhosttyKit"],
            exclude: [
                "Resources/ToolLogos/README.md",
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("Carbon"),
                .linkedLibrary("c++"),
            ]
        ),
        .testTarget(
            name: "AgentOSTests",
            dependencies: ["AgentOS"]
        ),
    ]
)
