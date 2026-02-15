// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AgentOS",
    platforms: [
        .macOS(.v15),
    ],
    targets: [
        .executableTarget(
            name: "AgentOS"
        ),
        .testTarget(
            name: "AgentOSTests",
            dependencies: ["AgentOS"]
        ),
    ]
)
