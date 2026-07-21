// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SEACore",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "SEACore",
            targets: ["SEACore"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SEACore",
            dependencies: [],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "SEACoreTests",
            dependencies: ["SEACore"],
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
