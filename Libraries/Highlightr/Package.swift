// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Highlightr",
    platforms: [
        .macOS(.v11),
        .iOS(.v11),
        .tvOS(.v11)
    ],
    products: [
        .library(
            name: "Highlightr",
            targets: ["Highlightr"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Highlightr",
            dependencies: [],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
