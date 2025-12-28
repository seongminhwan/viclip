// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VTool",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "VTool", targets: ["VTool"])
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "1.16.0"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern", from: "1.1.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.24.0"),
        .package(url: "https://github.com/raspu/Highlightr", from: "2.1.0")
    ],
    targets: [
        .executableTarget(
            name: "VTool",
            dependencies: [
                "HotKey",
                "KeyboardShortcuts",
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
                .product(name: "GRDB", package: "GRDB.swift"),
                "Highlightr"
            ],
            path: "Sources/VTool",
            exclude: ["Resources"]
        )
    ]
)
