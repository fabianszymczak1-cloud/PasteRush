// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PasteRush",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PasteRushCore", targets: ["PasteRushCore"]),
        .executable(name: "PasteRush", targets: ["PasteRushApp"]),
        .executable(name: "PasteRushTestRunner", targets: ["PasteRushTestRunner"]),
        .executable(name: "PasteRushBenchmark", targets: ["PasteRushBenchmark"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4")
    ],
    targets: [
        .target(
            name: "PasteRushCore",
            dependencies: [],
            path: "Sources/PasteRushCore",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "PasteRushApp",
            dependencies: [
                "PasteRushCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/PasteRushApp"
        ),
        .executableTarget(
            name: "PasteRushTestRunner",
            dependencies: ["PasteRushCore"],
            path: "Sources/PasteRushTestRunner"
        ),
        .executableTarget(
            name: "PasteRushBenchmark",
            dependencies: ["PasteRushCore"],
            path: "Sources/PasteRushBenchmark"
        ),
        .testTarget(
            name: "PasteRushTests",
            dependencies: ["PasteRushCore"],
            path: "Tests/PasteRushTests"
        )
    ]
)
