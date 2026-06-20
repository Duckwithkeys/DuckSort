// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PhotomatorSort",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "PhotomatorSort", targets: ["PhotomatorSort"])
    ],
    targets: [
        .executableTarget(
            name: "PhotomatorSort",
            path: "PhotomatorSort",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
