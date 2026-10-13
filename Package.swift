// swift-tools-version: 6.4
// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

import PackageDescription

/// The runtime/debug tooling extracted from the Axoloty build harness.
///
/// This package owns the `ax serve mqtt|mcp|dev` supervisor and its service
/// primitives. It is intentionally independent of the Axoloty repository
/// layout: it talks to a broker and to the `axoloty-mcp` product, never to the
/// build orchestration policy that stays in the `axoloty` repository.
let package = Package(
    name: "AxolotyDebug",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AxolotyDebug", targets: ["AxolotyDebug"]),
        // The standalone CLI that owns the serve mqtt|mcp|dev entry points.
        .executable(name: "axoloty-debug", targets: ["AxolotyDebugCLI"]),
        // The low-level process launch and signal-disposition shim.
        .library(name: "AxolotyProcessLauncher", targets: ["AxolotyProcessLauncher"]),
    ],
    targets: [
        .target(
            name: "AxolotyProcessLauncher",
            path: "Sources/AxolotyProcessLauncher",
            publicHeadersPath: "include"
        ),
        .target(
            name: "AxolotyDebug",
            dependencies: ["AxolotyProcessLauncher"],
            path: "Sources/AxolotyDebug"
        ),
        .executableTarget(
            name: "AxolotyDebugCLI",
            dependencies: ["AxolotyDebug"],
            path: "Sources/axoloty-debug"
        ),
        .testTarget(
            name: "AxolotyDebugTests",
            dependencies: ["AxolotyDebug"],
            path: "Tests/AxolotyDebugTests"
        ),
    ]
)
