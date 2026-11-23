// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Gantry",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "Gantry", targets: ["Gantry"]),
        .executable(name: "Gantry-plugins", targets: ["GantryPluginMCP"])
    ],
    targets: [
        .target(
            name: "GantryCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Gantry",
            dependencies: ["GantryCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "GantryPluginMCP",
            dependencies: ["GantryCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "GantryCoreTests",
            dependencies: ["GantryCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
