// swift-tools-version: 6.4
// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

import class Foundation.ProcessInfo
import PackageDescription

/// The runtime and debug tooling for the Axoloty stack.
///
/// This package owns everything that talks to a live Axoloty runtime: the
/// `axoloty-debug` serve supervisor, the object inspector, and the MCP server.
/// It depends on the published `Axoloty` library and reads no build or
/// repository policy.
let coreDependency: Package.Dependency = {
    let environment = ProcessInfo.processInfo.environment
    let localPaths = [
        environment["AXOLOTY_LOCAL_CORE_PATH"],
        environment["AXOLOTY_CORE_PATH"],
    ]
    if let localPath = localPaths.compactMap({ $0 }).first(where: { !$0.isEmpty }) {
        return .package(name: "Axoloty", path: localPath)
    }
    return .package(
        url: "https://github.com/phynics/axoloty.git",
        .upToNextMinor(from: "0.9.0")
    )
}()

let package = Package(
    name: "AxolotyDebug",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "axoloty-debug", targets: ["AxolotyDebugCLI"]),
        .executable(name: "axoloty-inspect", targets: ["AxolotyInspectorCLI"]),
        .executable(name: "axoloty-mcp", targets: ["AxolotyMCPServer"]),
        .library(name: "AxolotyDebug", targets: ["AxolotyDebug"]),
        .library(name: "AxolotyProcessLauncher", targets: ["AxolotyProcessLauncher"]),
    ],
    dependencies: [
        // Versioned Core URL dependency in released configuration, with local
        // development override via AXOLOTY_LOCAL_CORE_PATH / AXOLOTY_CORE_PATH.
        coreDependency,
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.14.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.101.2"),
    ],
    targets: [
        .target(
            name: "AxolotyProcessLauncher",
            path: "Sources/AxolotyProcessLauncher",
            publicHeadersPath: "include"
        ),
        .target(name: "AxolotyVersion", path: "Sources/AxolotyVersion"),
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
        .target(
            name: "AxolotyInspectorCore",
            dependencies: ["AxolotyVersion"],
            path: "Sources/AxolotyInspectorCore"
        ),
        .target(
            name: "AxolotyInspectorRuntime",
            dependencies: [
                .product(name: "Axoloty", package: "Axoloty"),
                "AxolotyInspectorCore",
            ],
            path: "Sources/AxolotyInspectorRuntime"
        ),
        .executableTarget(
            name: "AxolotyInspectorCLI",
            dependencies: [
                .product(name: "Axoloty", package: "Axoloty"),
                .product(name: "AxolotyMQTT", package: "Axoloty"),
                "AxolotyInspectorCore",
                "AxolotyInspectorRuntime",
            ],
            path: "Sources/axoloty-inspect"
        ),
        .target(
            name: "AxolotyMCP",
            dependencies: [
                .product(name: "Axoloty", package: "Axoloty"),
                "AxolotyInspectorCore",
                "AxolotyInspectorRuntime",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ],
            path: "Sources/AxolotyMCP"
        ),
        .executableTarget(
            name: "AxolotyMCPServer",
            dependencies: [
                .product(name: "Axoloty", package: "Axoloty"),
                .product(name: "AxolotyMQTT", package: "Axoloty"),
                "AxolotyDebug",
                "AxolotyMCP",
                "AxolotyInspectorCore",
                "AxolotyInspectorRuntime",
            ],
            path: "Sources/axoloty-mcp"
        ),
        .target(
            name: "AxolotyDebugTestSupport",
            path: "Tests/AxolotyDebugTestSupport"
        ),
        .testTarget(
            name: "AxolotyDebugTests",
            dependencies: ["AxolotyDebug", "AxolotyDebugTestSupport"],
            path: "Tests/AxolotyDebugTests"
        ),
        .testTarget(
            name: "AxolotyInspectorCoreTests",
            dependencies: ["AxolotyInspectorCore"],
            path: "Tests/AxolotyInspectorCoreTests"
        ),
        .testTarget(
            name: "AxolotyInspectorRuntimeTests",
            dependencies: [
                "AxolotyInspectorRuntime",
                "AxolotyInspectorCore",
                .product(name: "Axoloty", package: "Axoloty"),
            ],
            path: "Tests/AxolotyInspectorRuntimeTests"
        ),
        .testTarget(
            name: "AxolotyInspectorCLITests",
            dependencies: [
                .product(name: "Axoloty", package: "Axoloty"),
                "AxolotyInspectorCore",
                "AxolotyInspectorRuntime",
            ],
            path: "Tests/AxolotyInspectorCLITests"
        ),
        .testTarget(
            name: "AxolotyMCPTests",
            dependencies: [
                "AxolotyMCP",
                "AxolotyMCPServer",
                "AxolotyDebug",
                "AxolotyDebugTestSupport",
            ],
            path: "Tests/AxolotyMCPTests"
        ),
    ]
)
