// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

import AxolotyMCP
import AxolotyInspectorCore
import AxolotyDebug
import Foundation

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

let args = Array(CommandLine.arguments.dropFirst())

let helpText = """
Usage: axoloty-mcp [options]

Start an Axoloty MCP server using stdio or HTTP.

Options:
  --transport MODE        Use stdio or http (default: stdio).
  --listen-host HOST      HTTP bind address (default: 127.0.0.1).
  --listen-port PORT      HTTP listen port (default: 8765).
  --path PATH             HTTP endpoint path (default: /mcp).
  --broker-host HOST      MQTT broker host (default: localhost).
  --broker-port PORT      MQTT broker port (default: 1883).
  --namespace NAMESPACE   Coaty namespace (default: -).
  --connect-timeout TIME  Broker readiness timeout (default: 10s).
  --enable-controls       Allow active tools such as axoloty_discover_objects
                          (default: read-only).
  --include-payloads      Include raw object payloads and private data
                          (default: redacted).
  --access-token-file PATH
                          Require this bearer token on every HTTP request.
                          Required for a non-loopback --listen-host.
  --help                  Show this help.
"""

if args.contains("--help") || args.contains("-h") {
    print(helpText)
    Foundation.exit(0)
}

var brokerHost = ProcessInfo.processInfo.environment["AXOLOTY_MQTT_HOST"] ?? "localhost"
var brokerPortRaw = ProcessInfo.processInfo.environment["AXOLOTY_MQTT_PORT"] ?? "1883"
var namespace = ProcessInfo.processInfo.environment["AXOLOTY_NAMESPACE"] ?? "-"

var transport = "stdio"
var listenHost = "127.0.0.1"
var listenPortRaw = ProcessInfo.processInfo.environment["AXOLOTY_MCP_PORT"] ?? "8765"
var mcpPath = "/mcp"
var connectTimeout: Duration = .seconds(10)
var enableControls = false
var includePayloads = false
var accessTokenPath: String?

var i = 0
while i < args.count {
    switch args[i] {
    case "--broker-host":
        guard i + 1 < args.count else {
            FileHandle.standardError.write(Data("error: --broker-host requires a value\n".utf8))
            Foundation.exit(64)
        }
        brokerHost = args[i + 1]
        i += 2
    case "--broker-port":
        guard i + 1 < args.count else {
            FileHandle.standardError.write(Data("error: --broker-port requires a value\n".utf8))
            Foundation.exit(64)
        }
        brokerPortRaw = args[i + 1]
        i += 2
    case "--namespace":
        guard i + 1 < args.count else {
            FileHandle.standardError.write(Data("error: --namespace requires a value\n".utf8))
            Foundation.exit(64)
        }
        namespace = args[i + 1]
        i += 2
    case "--connect-timeout":
        guard i + 1 < args.count else {
            FileHandle.standardError.write(Data("error: --connect-timeout requires a value\n".utf8))
            Foundation.exit(64)
        }
        guard let value = InspectorDuration(rawValue: args[i + 1])?.value else {
            FileHandle.standardError.write(Data("error: invalid connect timeout: \(args[i + 1]) (use a positive duration such as 10s, 2m, or 1h; maximum 24h)\n".utf8))
            Foundation.exit(64)
        }
        connectTimeout = value
        i += 2
    case "--transport":
        guard i + 1 < args.count else {
            FileHandle.standardError.write(Data("error: --transport requires a value\n".utf8))
            Foundation.exit(64)
        }
        transport = args[i + 1]
        i += 2
    case "--listen-host":
        guard i + 1 < args.count else {
            FileHandle.standardError.write(Data("error: --listen-host requires a value\n".utf8))
            Foundation.exit(64)
        }
        listenHost = args[i + 1]
        i += 2
    case "--listen-port":
        guard i + 1 < args.count else {
            FileHandle.standardError.write(Data("error: --listen-port requires a value\n".utf8))
            Foundation.exit(64)
        }
        listenPortRaw = args[i + 1]
        i += 2
    case "--path":
        guard i + 1 < args.count else {
            FileHandle.standardError.write(Data("error: --path requires a value\n".utf8))
            Foundation.exit(64)
        }
        mcpPath = args[i + 1]
        i += 2
    case "--enable-controls":
        enableControls = true
        i += 1
    case "--include-payloads":
        includePayloads = true
        i += 1
    case "--access-token-file":
        guard i + 1 < args.count else {
            FileHandle.standardError.write(Data("error: --access-token-file requires a value\n".utf8))
            Foundation.exit(64)
        }
        accessTokenPath = args[i + 1]
        i += 2
    case let argument where argument.hasPrefix("--path="):
        mcpPath = String(argument.dropFirst("--path=".count))
        i += 1
    case let argument where argument.hasPrefix("--access-token-file="):
        accessTokenPath = String(argument.dropFirst("--access-token-file=".count))
        i += 1
    default:
        FileHandle.standardError.write(Data("error: unknown argument: \(args[i])\n".utf8))
        Foundation.exit(64)
    }
}

guard let brokerPort = UInt16(brokerPortRaw), brokerPort > 0 else {
    FileHandle.standardError.write(Data("error: invalid broker port: \(brokerPortRaw) (must be 1–65535)\n".utf8))
    Foundation.exit(64)
}
guard let listenPort = UInt16(listenPortRaw), listenPort > 0 else {
    FileHandle.standardError.write(Data("error: invalid listen port: \(listenPortRaw) (must be 1–65535)\n".utf8))
    Foundation.exit(64)
}

if transport == "http" {
    switch MCPPathPolicy.validate(mcpPath) {
    case .success:
        break
    case .failure(let error):
        FileHandle.standardError.write(Data("error: \(error.userFriendlyMessage)\n".utf8))
        Foundation.exit(64)
    }
}

if transport != "http", accessTokenPath != nil {
    FileHandle.standardError.write(Data("error: --access-token-file is only valid with --transport http\n".utf8))
    Foundation.exit(64)
}

if transport == "http" {
    if accessTokenPath == nil, !MCPAccessPolicy.isLoopbackHost(listenHost) {
        FileHandle.standardError.write(Data(
            "error: non-loopback HTTP binding requires --access-token-file\n".utf8
        ))
        Foundation.exit(64)
    }
    if (accessTokenPath != nil || !MCPAccessPolicy.isLoopbackHost(listenHost)),
        enableControls || includePayloads
    {
        FileHandle.standardError.write(Data(
            "error: remote HTTP binding is always read-only; --enable-controls and --include-payloads are local-only\n".utf8
        ))
        Foundation.exit(64)
    }
}

var accessProtection: MCPAccessProtection?
if let accessTokenPath {
    let token: String
    do {
        token = try readAccessToken(at: accessTokenPath)
    } catch {
        FileHandle.standardError.write(Data(
            "error: unable to read access token file: \(accessTokenPath)\n".utf8
        ))
        Foundation.exit(64)
    }
    guard let protection = MCPAccessProtection(bearerToken: token) else {
        FileHandle.standardError.write(Data(
            "error: access token file is empty or contains invalid whitespace: \(accessTokenPath)\n".utf8
        ))
        Foundation.exit(64)
    }
    accessProtection = protection
}

let exitCode = await runMCPServer(
    host: brokerHost,
    port: brokerPort,
    namespace: namespace,
    transport: transport,
    listenHost: listenHost,
    listenPort: listenPort,
    path: mcpPath,
    connectTimeout: connectTimeout,
    accessPolicy: MCPAccessPolicy(controlsEnabled: enableControls, includePayloads: includePayloads),
    accessProtection: accessProtection
)
Foundation.exit(exitCode)

private enum AccessTokenFileError: Error {
    case openFailed
    case unsafeFile
}

private func readAccessToken(at path: String) throws(AccessTokenFileError) -> String {
    let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    guard descriptor >= 0 else { throw .openFailed }
    defer { _ = close(descriptor) }

    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0 else { throw .unsafeFile }
    let isRegularFile = metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
    let isPrivate = metadata.st_mode & 0o077 == 0
    guard isRegularFile,
        isPrivate,
        metadata.st_size > 0,
        metadata.st_size <= off_t(MCPAccessProtection.maximumTokenBytes)
    else {
        throw .unsafeFile
    }

    var bytes: [UInt8] = []
    bytes.reserveCapacity(Int(metadata.st_size))
    while bytes.count <= MCPAccessProtection.maximumTokenBytes {
        let remaining = MCPAccessProtection.maximumTokenBytes + 1 - bytes.count
        var buffer = [UInt8](repeating: 0, count: min(1_024, remaining))
        let readCount = buffer.withUnsafeMutableBytes { bufferPointer in
            read(descriptor, bufferPointer.baseAddress, bufferPointer.count)
        }
        if readCount < 0 {
            if errno == EINTR { continue }
            throw .unsafeFile
        }
        if readCount == 0 { break }
        bytes.append(contentsOf: buffer.prefix(Int(readCount)))
    }

    guard bytes.count <= MCPAccessProtection.maximumTokenBytes,
        let token = String(bytes: bytes, encoding: .utf8)
    else {
        throw .unsafeFile
    }
    return token
}

@MainActor
func runMCPServer(
    host: String,
    port: UInt16,
    namespace: String,
    transport: String,
    listenHost: String,
    listenPort: UInt16,
    path: String,
    connectTimeout: Duration,
    accessPolicy: MCPAccessPolicy,
    accessProtection: MCPAccessProtection? = nil
) async -> Int32 {
    do {
        let server = try AxolotyMCPServer(
            host: host,
            port: port,
            namespace: namespace,
            connectTimeout: connectTimeout,
            accessPolicy: accessPolicy,
            transport: MQTTInspectorTransport.factory
        )
        switch transport {
        case "stdio":
            try await server.startStdio()
        case "http":
            try await server.startHTTP(
                listenHost: listenHost,
                listenPort: listenPort,
                path: path,
                accessProtection: accessProtection
            )
        default:
            FileHandle.standardError.write(Data("error: unknown transport: \(transport)\n".utf8))
            return 64
        }
        return 0
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        return 70
    }
}
