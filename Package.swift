// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GridOverlay",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "GridOverlay",
            targets: ["GridOverlay"]
        )
    ],
    targets: [
        .executableTarget(
            name: "GridOverlay",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
