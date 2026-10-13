// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

import AxolotyDebug
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())

let helpText = """
Usage: axoloty-debug <command>

Runtime and debug tooling for the Axoloty stack.

Commands:
  serve mqtt [options]   Start a local Mosquitto broker.
  serve mcp [options]    Start an Axoloty MCP server (stdio or HTTP).
  serve dev [options]    Start MQTT and MCP as a supervised development stack.
  help, --help, -h       Show this help.

Run `axoloty-debug serve <subcommand> --help` for subcommand options.
"""

if arguments.isEmpty || arguments.first == "help" || arguments.first == "--help" || arguments.first == "-h" {
    print(helpText)
    Foundation.exit(0)
}

guard arguments.first == "serve" else {
    FileHandle.standardError.write(Data("error: unsupported axoloty-debug command: \(arguments[0])\n\n\(helpText)\n".utf8))
    Foundation.exit(64)
}

let session = AxolotyServeSession(
    executableName: "axoloty-debug",
    environment: ProcessInfo.processInfo.environment,
    installSignalHandler: true
)

let result = session.run(arguments: Array(arguments.dropFirst()))
FileHandle.standardOutput.write(Data(result.standardOutput.utf8))
FileHandle.standardError.write(Data(result.standardError.utf8))
Foundation.exit(result.exitCode)
