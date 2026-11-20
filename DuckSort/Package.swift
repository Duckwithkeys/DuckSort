// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DuckSort",
    platforms: [
        .macOS("27.0")
    ],
    products: [
        .executable(name: "DuckSort", targets: ["DuckSort"])
    ],
    targets: [
        .executableTarget(
            name: "DuckSort",
            path: "DuckSort",
            exclude: ["Info.plist"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "DuckSortTests",
            dependencies: ["DuckSort"],
            path: "Tests/DuckSortTests"
        )
    ]
)
