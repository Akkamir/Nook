// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Nook",
    targets: [
        .executableTarget(
            name: "NookDaemon",
            path: "Sources/NookDaemon"
        ),
        .testTarget(
            name: "NookTests",
            dependencies: ["NookDaemon"],
            path: "Tests/NookTests"
        )
    ]
)
