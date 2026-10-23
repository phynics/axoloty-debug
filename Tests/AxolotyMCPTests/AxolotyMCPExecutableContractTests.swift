// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

import AxolotyDebug
import AxolotyMCP
import Foundation
import Testing

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

@Test("MCP executable rejects invalid broker port")
func executableRejectsInvalidBrokerPort() throws {
    let result = try runMCPExecutable(arguments: ["--broker-port", "0"])

    #expect(result.exitCode == 64)
    #expect(result.standardError.contains("invalid broker port"))
}

@Test("MCP executable rejects invalid listen port")
func executableRejectsInvalidListenPort() throws {
    let result = try runMCPExecutable(arguments: ["--listen-port", "70000"])

    #expect(result.exitCode == 64)
    #expect(result.standardError.contains("invalid listen port"))
}

@Test("MCP executable rejects invalid endpoint path with managed-service error")
func executableRejectsInvalidEndpointPathWithManagedServiceError() throws {
    let result = try runMCPExecutable(
        arguments: ["--transport", "http", "--path", "mcp"]
    )

    #expect(result.exitCode == 64)
    #expect(result.standardError == "error: invalid endpoint path: mcp (must start with /)\n")
}

@Test("Direct and managed MCP path validation have identical outcomes")
func mcpPathValidationParityMatrix() throws {
    let cases: [(path: String, expectedError: AxolotyServeError?)] = [
        ("", .invalidPath("")),
        ("mcp", .invalidPath("mcp")),
        ("/api/mcp", nil),
    ]

    for testCase in cases {
        let directResult = try runMCPExecutableForPathValidation(
            arguments: ["--transport", "http", "--path=\(testCase.path)", "--connect-timeout", "30s"]
        )
        let managedResult = AxolotyServeParser().parse(
            arguments: ["mcp", "--transport", "http", "--path=\(testCase.path)"],
            environment: [:]
        )

        if let expectedError = testCase.expectedError {
            let expectedMessage = expectedError.userFriendlyMessage
            #expect(directResult == .rejected(
                exitCode: 64,
                standardError: "error: \(expectedMessage)\n"
            ))
            guard case .failure(let managedError) = managedResult else {
                Issue.record("managed validation accepted invalid path '\(testCase.path)'")
                continue
            }
            #expect(managedError == expectedError)
            #expect(managedError.userFriendlyMessage == expectedMessage)
        } else {
            #expect(directResult == .accepted)
            guard case .success(.mcp(let configuration)) = managedResult else {
                Issue.record("managed validation rejected valid path '\(testCase.path)'")
                continue
            }
            #expect(configuration.path == testCase.path)
        }
    }
}

@Test("MCP executable routes --path= through shared validation")
func executableRejectsEmptyEqualsPathWithManagedServiceError() throws {
    let result = try runMCPExecutable(arguments: ["--transport", "http", "--path="])

    #expect(result.exitCode == 64)
    #expect(result.standardError == "error: invalid endpoint path:  (must start with /)\n")
}

@Test("Managed MCP parser distinguishes missing from explicitly empty path")
func managedParserDistinguishesMissingAndEmptyPath() {
    let missing = AxolotyServeParser().parse(
        arguments: ["mcp", "--transport", "http", "--path"],
        environment: [:]
    )
    let empty = AxolotyServeParser().parse(
        arguments: ["mcp", "--transport", "http", "--path", ""],
        environment: [:]
    )

    #expect(missing == .failure(.missingValue("path")))
    #expect(empty == .failure(.invalidPath("")))
}

@Test("MCP executable rejects invalid connect timeout")
func executableRejectsInvalidConnectTimeout() throws {
    let result = try runMCPExecutable(
        arguments: ["--connect-timeout", "9223372036854775807m"]
    )

    #expect(result.exitCode == 64)
    #expect(result.standardError.contains("invalid connect timeout"))
}

@Test("MCP executable rejects invalid environment ports")
func executableRejectsInvalidEnvironmentPorts() throws {
    let brokerResult = try runMCPExecutable(
        arguments: [],
        environment: ["AXOLOTY_MQTT_PORT": "invalid"]
    )
    let listenResult = try runMCPExecutable(
        arguments: [],
        environment: ["AXOLOTY_MCP_PORT": "0"]
    )

    #expect(brokerResult.exitCode == 64)
    #expect(brokerResult.standardError.contains("invalid broker port"))
    #expect(listenResult.exitCode == 64)
    #expect(listenResult.standardError.contains("invalid listen port"))
}

@Test("MCP executable CLI port overrides invalid environment value")
func executableCLIOverridesInvalidEnvironmentPort() throws {
    let result = try runMCPExecutable(
        arguments: ["--broker-port", "1883", "--transport", "invalid"],
        environment: ["AXOLOTY_MQTT_PORT": "0"]
    )

    #expect(result.exitCode == 64)
    #expect(result.standardError.contains("unknown transport"))
    #expect(!result.standardError.contains("invalid broker port"))
}

@Test("MCP executable requires an access token for a non-loopback HTTP binding")
func executableRequiresTokenForRemoteBinding() throws {
    let result = try runMCPExecutable(
        arguments: ["--transport", "http", "--listen-host", "0.0.0.0"]
    )

    #expect(result.exitCode == 64)
    #expect(result.standardError.contains("non-loopback HTTP binding requires --access-token-file"))
}

@Test("MCP executable rejects local controls on a remote binding")
func executableRejectsControlsOnRemoteBinding() throws {
    let tokenFile = try writeAccessToken("remote-token")
    defer { try? FileManager.default.removeItem(at: tokenFile) }

    let result = try runMCPExecutable(arguments: [
        "--transport", "http",
        "--listen-host", "0.0.0.0",
        "--enable-controls",
        "--access-token-file", tokenFile.path,
    ])

    #expect(result.exitCode == 64)
    #expect(result.standardError.contains("remote HTTP binding is always read-only"))
}

@Test("MCP executable rejects access tokens without HTTP")
func executableRejectsAccessTokenWithoutHTTP() throws {
    let tokenFile = try writeAccessToken("stdio-token")
    defer { try? FileManager.default.removeItem(at: tokenFile) }

    let result = try runMCPExecutable(arguments: [
        "--access-token-file", tokenFile.path,
    ])

    #expect(result.exitCode == 64)
    #expect(result.standardError.contains("--access-token-file is only valid with --transport http"))
}

@Test("MCP executable rejects an unreadable or empty access token file")
func executableRejectsInvalidAccessTokenFile() throws {
    let missing = try runMCPExecutable(arguments: [
        "--transport", "http",
        "--access-token-file", "/nonexistent/axoloty-mcp-token",
    ])
    #expect(missing.exitCode == 64)
    #expect(missing.standardError.contains("unable to read access token file"))

    let emptyFile = try writeAccessToken("\n\t")
    defer { try? FileManager.default.removeItem(at: emptyFile) }
    let empty = try runMCPExecutable(arguments: [
        "--transport", "http",
        "--access-token-file", emptyFile.path,
    ])
    #expect(empty.exitCode == 64)
    #expect(empty.standardError.contains("access token file is empty or contains invalid whitespace"))
}

@Test("MCP executable rejects access-token files with unsafe permissions")
func executableRejectsWorldReadableAccessTokenFile() throws {
    let tokenFile = try writeAccessToken("remote-token")
    defer { try? FileManager.default.removeItem(at: tokenFile) }
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: tokenFile.path)

    let result = try runMCPExecutable(arguments: [
        "--transport", "http",
        "--access-token-file", tokenFile.path,
    ])

    #expect(result.exitCode == 64)
    #expect(result.standardError.contains("unable to read access token file"))
}

@Test("MCP executable rejects oversized token files and FIFOs without blocking")
func executableRejectsOversizedAndSpecialAccessTokenFiles() throws {
    let oversized = try writeAccessToken(String(repeating: "a", count: MCPAccessProtection.maximumTokenBytes + 1))
    defer { try? FileManager.default.removeItem(at: oversized) }
    let oversizedResult = try runMCPExecutable(arguments: [
        "--transport", "http",
        "--access-token-file", oversized.path,
    ])
    #expect(oversizedResult.exitCode == 64)
    #expect(oversizedResult.standardError.contains("unable to read access token file"))

    let fifo = FileManager.default.temporaryDirectory
        .appendingPathComponent("axoloty-mcp-token-fifo-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: fifo) }
    #expect(mkfifo(fifo.path, 0o600) == 0)
    let fifoResult = try runMCPExecutable(arguments: [
        "--transport", "http",
        "--access-token-file", fifo.path,
    ])
    #expect(fifoResult.exitCode == 64)
    #expect(fifoResult.standardError.contains("unable to read access token file"))
}

private func writeAccessToken(_ contents: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("axoloty-mcp-token-\(UUID().uuidString)")
    try Data(contents.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    return url
}
