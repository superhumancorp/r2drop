// swift-tools-version: 5.9
// Packages/R2Core/Package.swift
// Swift package providing shared models, config, queue, and history managers for R2Drop.

import PackageDescription

let package = Package(
    name: "R2Core",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "R2Core", targets: ["R2Core"])
    ],
    targets: [
        .target(
            name: "R2Core",
            path: "Sources/R2Core"
        ),
        .testTarget(
            name: "R2CoreTests",
            dependencies: ["R2Core"],
            path: "Tests/R2CoreTests"
        )
    ]
)
