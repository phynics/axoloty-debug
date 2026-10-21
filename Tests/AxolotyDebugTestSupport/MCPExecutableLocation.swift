// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

import Foundation

/// Locates the `axoloty-mcp` executable that belongs to the current test run.
public enum MCPExecutableLocation {
    /// Returns the `axoloty-mcp` executable for the current test run.
    ///
    /// The search starts beside the running test executable and walks up to the
    /// enclosing build products directory. This finds the freshly built product
    /// in standard SwiftPM layouts and in macOS test bundles. If no built product
    /// is found, the standard `.build/debug` layout and the
    /// `AXOLOTY_MCP_EXECUTABLE` environment variable are used as fallbacks.
    ///
    /// - Returns: The executable URL, or `nil` when no executable exists.
    public static func locate() -> URL? {
        for directory in candidateDirectories() {
            let candidate = directory.appendingPathComponent("axoloty-mcp")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        let standardProduct = URL(fileURLWithPath: ".build/debug/axoloty-mcp")
        if FileManager.default.isExecutableFile(atPath: standardProduct.path) {
            return standardProduct
        }

        let environment = ProcessInfo.processInfo.environment
        if let configured = environment["AXOLOTY_MCP_EXECUTABLE"],
           FileManager.default.isExecutableFile(atPath: configured) {
            return URL(fileURLWithPath: configured)
        }

        return nil
    }

    private static func candidateDirectories() -> [URL] {
        guard let executablePath = CommandLine.arguments.first else { return [] }
        var directories: [URL] = []
        var directory = URL(fileURLWithPath: executablePath).deletingLastPathComponent()
        while true {
            directories.append(directory)
            if directory.lastPathComponent == "Products" || directory.lastPathComponent == ".build" {
                break
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path {
                break
            }
            directory = parent
        }
        return directories
    }
}
