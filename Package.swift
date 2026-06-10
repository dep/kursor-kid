// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "KursorKid",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "KursorKidCore"),
        .executableTarget(
            name: "KursorKid",
            dependencies: ["KursorKidCore"]
        ),
        .testTarget(
            name: "KursorKidCoreTests",
            dependencies: ["KursorKidCore"]
        ),
    ]
)
