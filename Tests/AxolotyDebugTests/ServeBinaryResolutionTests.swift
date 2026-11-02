// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

import AxolotyDebugTestSupport
import Foundation
import Testing

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Runs the built `axoloty-debug` binary to prove which `axoloty-mcp` it starts.
///
/// The unit tests in `AxolotyDevelopmentServiceTests` use a fake file system and
/// cannot see how the executable's own location is discovered (symlinks,
/// relative invocation, `PATH` lookup). These tests copy the real binary next to
/// a stand-in `axoloty-mcp`, plant decoys in the current directory and in
/// `PATH`, and check which one ran from marker files.
@Suite(.serialized)
struct ServeBinaryResolutionTests {
    private struct Outcome {
        var exitCode: Int32
        var standardError: String
        var markers: Set<String>
    }

    /// Scratch tree: `real/` (binary + sibling), `alone/` (binary only),
    /// `link/` (symlink to the real binary), `decoy_cwd/` and `decoy_path/`.
    private struct Layout {
        let root: URL
        var marks: URL { root.appendingPathComponent("marks") }
        func path(_ components: String...) -> String {
            components.reduce(root) { $0.appendingPathComponent($1) }.path
        }
    }

    private static func script(marker: String, marks: URL, exitCode: Int32) -> String {
        "#!/bin/sh\ntouch '\(marks.path)/\(marker)'\nexit \(exitCode)\n"
    }

    private static func makeLayout() throws -> Layout? {
        // The Core container launcher path outranks a sibling by design.
        if FileManager.default.fileExists(atPath: "/opt/axoloty/bin/axoloty-mcp") { return nil }
        let binary = try #require(MCPExecutableLocation.locateProduct(named: "axoloty-debug"))
        let fileManager = FileManager.default
        let layout = Layout(root: fileManager.temporaryDirectory
            .appendingPathComponent("axoloty-serve-resolution-\(UUID().uuidString)"))
        for directory in ["real", "alone", "link", "decoy_cwd", "decoy_path", "marks"] {
            try fileManager.createDirectory(
                at: layout.root.appendingPathComponent(directory), withIntermediateDirectories: true
            )
        }
        try fileManager.copyItem(at: binary, to: URL(fileURLWithPath: layout.path("real", "axoloty-debug")))
        try fileManager.copyItem(at: binary, to: URL(fileURLWithPath: layout.path("alone", "axoloty-debug")))
        try fileManager.createSymbolicLink(
            atPath: layout.path("link", "axoloty-debug"), withDestinationPath: layout.path("real", "axoloty-debug")
        )
        let scripts = [
            ("real", "SIBLING-RAN", Int32(7)),
            ("decoy_cwd", "DECOY-CWD-RAN", Int32(1)),
            ("decoy_path", "DECOY-PATH-RAN", Int32(1)),
        ]
        for (directory, marker, code) in scripts {
            let url = URL(fileURLWithPath: layout.path(directory, "axoloty-mcp"))
            try script(marker: marker, marks: layout.marks, exitCode: code).write(to: url, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        return layout
    }

    private static func run(
        _ layout: Layout,
        shell command: String,
        path: String,
        extraEnvironment: [String: String] = [:]
    ) throws -> Outcome {
        for marker in try FileManager.default.contentsOfDirectory(atPath: layout.marks.path) {
            try FileManager.default.removeItem(at: layout.marks.appendingPathComponent(marker))
        }
        var environment = ProcessInfo.processInfo.environment
        environment["AXOLOTY_MCP_EXECUTABLE"] = nil
        environment["AXOLOTY_MOSQUITTO_EXECUTABLE"] = nil
        environment["PATH"] = path
        environment.merge(extraEnvironment) { $1 }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "exec " + command]
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: layout.path("decoy_cwd"))
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        // A stand-in that exits does not end the run: the supervisor waits out its
        // readiness deadline. Once a marker shows a binary started, allow a short
        // window for a wrongly chosen second binary to show too, then stop.
        let deadline = Date().addingTimeInterval(30)
        var firstMarker: Date?
        while process.isRunning, Date() < deadline {
            let seen = (try? FileManager.default.contentsOfDirectory(atPath: layout.marks.path)) ?? []
            if !seen.isEmpty, firstMarker == nil { firstMarker = Date() }
            if let firstMarker, Date().timeIntervalSince(firstMarker) > 0.7 { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        // The stand-ins never become ready, so the supervisor would otherwise wait out
        // its readiness deadline; stop it without waiting.
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let markers = Set(try FileManager.default.contentsOfDirectory(atPath: layout.marks.path))
        return Outcome(
            exitCode: process.terminationStatus,
            standardError: String(decoding: data, as: UTF8.self),
            markers: markers
        )
    }

    private static let serve = "serve mcp --transport http --listen-port 18733"

    @Test("axoloty-debug starts its sibling axoloty-mcp, never a decoy, however it is invoked")
    func siblingWinsOverDecoys() throws {
        guard let layout = try Self.makeLayout() else { return }
        defer { try? FileManager.default.removeItem(at: layout.root) }
        let base = "/usr/bin:/bin"
        let decoyPath = layout.path("decoy_path")

        let invocations: [(String, String, String)] = [
            ("symlink found through PATH", "axoloty-debug \(Self.serve)", "\(decoyPath):\(layout.path("link")):\(base)"),
            ("absolute symlink path", "\(layout.path("link", "axoloty-debug")) \(Self.serve)", "\(decoyPath):\(base)"),
            ("relative path from the decoy directory", "../real/axoloty-debug \(Self.serve)", "\(decoyPath):\(base)"),
            ("PATH lookup behind a decoy directory", "axoloty-debug \(Self.serve)", "\(decoyPath):\(layout.path("real")):\(base)"),
        ]
        for (name, command, path) in invocations {
            let outcome = try Self.run(layout, shell: command, path: path)
            #expect(outcome.markers == ["SIBLING-RAN"], "\(name): ran \(outcome.markers.sorted()); stderr: \(outcome.standardError)")
        }
    }

    @Test("Without a sibling, axoloty-debug reports the missing binary and runs no decoy")
    func missingSiblingDoesNotFallBackToDecoys() throws {
        guard let layout = try Self.makeLayout() else { return }
        defer { try? FileManager.default.removeItem(at: layout.root) }
        let path = "\(layout.path("decoy_path")):\(layout.path("alone")):/usr/bin:/bin"

        let outcome = try Self.run(layout, shell: "axoloty-debug \(Self.serve)", path: path)
        #expect(outcome.exitCode == 69)
        #expect(outcome.standardError.contains("executable not found"))
        #expect(outcome.markers.isEmpty, "ran \(outcome.markers.sorted())")
    }

    @Test("An absolute AXOLOTY_MCP_EXECUTABLE runs; a bare name is rejected instead of searching the current directory")
    func overrideMustBeAbsolute() throws {
        guard let layout = try Self.makeLayout() else { return }
        defer { try? FileManager.default.removeItem(at: layout.root) }
        let path = "\(layout.path("decoy_path")):\(layout.path("alone")):/usr/bin:/bin"

        let absolute = try Self.run(
            layout, shell: "axoloty-debug \(Self.serve)", path: path,
            extraEnvironment: ["AXOLOTY_MCP_EXECUTABLE": layout.path("real", "axoloty-mcp")]
        )
        #expect(absolute.markers == ["SIBLING-RAN"], "ran \(absolute.markers.sorted())")

        let bare = try Self.run(
            layout, shell: "axoloty-debug \(Self.serve)", path: path,
            extraEnvironment: ["AXOLOTY_MCP_EXECUTABLE": "axoloty-mcp"]
        )
        #expect(bare.exitCode == 64)
        #expect(bare.standardError.contains("AXOLOTY_MCP_EXECUTABLE must be an absolute path"))
        #expect(bare.markers.isEmpty, "ran \(bare.markers.sorted())")
    }
}
