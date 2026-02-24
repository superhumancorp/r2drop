// swift-tools-version: 5.9
// Packages/R2Bridge/Package.swift
// Swift package wrapping the Rust FFI static library (libr2_ffi.a).
// Links the C header via R2BridgeC module and provides Swift async wrappers.

import PackageDescription

let package = Package(
    name: "R2Bridge",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "R2Bridge", targets: ["R2Bridge"])
    ],
    targets: [
        // C target exposing the r2_ffi.h header via module map.
        // The actual static library (libr2_ffi.a) is linked at the Xcode project level
        // because SPM cannot link pre-built static libraries directly.
        .target(
            name: "R2BridgeC",
            path: "Sources/R2BridgeC",
            publicHeadersPath: "include"
        ),
        // Swift wrapper providing async APIs over the C FFI.
        .target(
            name: "R2Bridge",
            dependencies: ["R2BridgeC"],
            path: "Sources/R2Bridge"
        )
    ]
)
