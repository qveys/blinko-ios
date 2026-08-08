// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BlinkoApp",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "BlinkoApp", targets: ["BlinkoApp"])
    ],
    dependencies: [
        // Add Swift dependencies here via SPM
        // Example: .package(url: "https://github.com/onevcat/Kingfisher.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "BlinkoApp",
            dependencies: [],
            path: "Sources/BlinkoApp",
            resources: [
                .process("../../Resources")
            ]
        ),
        .testTarget(
            name: "BlinkoAppTests",
            dependencies: ["BlinkoApp"],
            path: "Tests/BlinkoAppTests"
        )
    ]
)
