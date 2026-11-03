// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

import AxolotyDebugTestSupport
import AxolotyVersion
import Foundation
import Testing

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Runs each built executable with `--version` and checks the shared output.
///
/// `axoloty-mcp` speaks MCP over stdout under the stdio transport, so these
/// tests keep its stdin open: a binary that started a server instead of
/// printing the version would not exit.
@Suite(.serialized)
struct VersionFlagTests {
    private struct Outcome {
        var exitCode: Int32
        var standardOutput: String
        var standardError: String
        var timedOut: Bool
    }

    private static let executables = ["axoloty-debug", "axoloty-inspect", "axoloty-mcp"]

    private static func run(_ name: String, arguments: [String], environment overrides: [String: String] = [:]) throws -> Outcome {
        let executable = try #require(MCPExecutableLocation.locateProduct(named: name), "\(name) was not built")
        var environment = ProcessInfo.processInfo.environment
        environment["AXOLOTY_VERSION"] = nil
        environment.merge(overrides) { $1 }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        try process.run()

        let deadline = Date().addingTimeInterval(10)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        let timedOut = process.isRunning
        if timedOut { kill(process.processIdentifier, SIGKILL) }
        try? input.fileHandleForWriting.close()
        let standardOutput = output.fileHandleForReading.readDataToEndOfFile()
        let standardError = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Outcome(
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: standardOutput, as: UTF8.self),
            standardError: String(decoding: standardError, as: UTF8.self),
            timedOut: timedOut
        )
    }

    @Test("The shared formatter names the executable and the version")
    func versionLineFormat() {
        #expect(AxolotyVersion.versionLine(executableName: "tool", environment: [:]) == "tool \(AxolotyVersion.compiledVersion)")
        #expect(AxolotyVersion.versionLine(executableName: "tool", environment: ["AXOLOTY_VERSION": "9.9.9"]) == "tool 9.9.9")
    }

    @Test("Every binary prints its name and the compiled version, and nothing else", arguments: executables)
    func printsCompiledVersion(name: String) throws {
        for flag in ["--version", "-v"] {
            let outcome = try Self.run(name, arguments: [flag])
            #expect(!outcome.timedOut, "\(name) \(flag) did not exit")
            #expect(outcome.exitCode == 0, "\(name) \(flag): \(outcome.standardError)")
            #expect(outcome.standardOutput == "\(name) \(AxolotyVersion.compiledVersion)\n", "\(name) \(flag)")
            #expect(outcome.standardError.isEmpty, "\(name) \(flag): \(outcome.standardError)")
        }
    }

    @Test("An explicit AXOLOTY_VERSION is reported identically by every binary", arguments: executables)
    func honoursVersionOverride(name: String) throws {
        let outcome = try Self.run(name, arguments: ["--version"], environment: ["AXOLOTY_VERSION": "9.9.9"])
        #expect(outcome.exitCode == 0)
        #expect(outcome.standardOutput == "\(name) 9.9.9\n")
    }

    @Test("axoloty-mcp prints the version before starting a stdio or HTTP server")
    func mcpVersionNeverStartsServer() throws {
        for arguments in [
            ["--transport", "stdio", "--version"],
            ["--transport", "http", "--listen-port", "18734", "--version"],
            ["--broker-host", "192.0.2.1", "--connect-timeout", "1h", "--version"],
        ] {
            let outcome = try Self.run("axoloty-mcp", arguments: arguments)
            #expect(!outcome.timedOut, "axoloty-mcp \(arguments) did not exit")
            #expect(outcome.exitCode == 0, "\(arguments): \(outcome.standardError)")
            #expect(outcome.standardOutput == "axoloty-mcp \(AxolotyVersion.compiledVersion)\n", "\(arguments)")
            #expect(outcome.standardError.isEmpty, "\(arguments): \(outcome.standardError)")
        }
    }

    @Test("Without --version, axoloty-debug and axoloty-mcp keep their existing argument handling")
    func otherArgumentsUnchanged() throws {
        let debug = try Self.run("axoloty-debug", arguments: ["bogus"])
        #expect(debug.exitCode == 64)
        #expect(debug.standardOutput.isEmpty)
        #expect(debug.standardError.contains("unsupported axoloty-debug command: bogus"))

        let mcp = try Self.run("axoloty-mcp", arguments: ["--bogus"])
        #expect(mcp.exitCode == 64)
        #expect(mcp.standardOutput.isEmpty)
        #expect(mcp.standardError.contains("unknown argument: --bogus"))
    }
}
