// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

import Foundation

/// Parses and executes the `serve` subcommands against a live development stack.
///
/// The session is the debug package's public entry point. It owns no build
/// policy: it starts a local Mosquitto broker, supervises the `axoloty-mcp`
/// product, or runs both together.
public final class AxolotyServeSession: Sendable {
    private let executableName: String
    private let environment: [String: String]
    private let fileSystem: any AxolotyDebugFileSystem
    private let processRunnerFactory: @Sendable () -> any AxolotyManagedProcessRunning
    private let portProbe: any AxolotyServiceProbing
    private let tempDirProvider: any AxolotyTempDirectoryProvider
    private let installSignalHandler: Bool
    private let cancellation = AxolotyDebugCancellation()

    /// Creates a serve session.
    ///
    /// - Parameters:
    ///   - executableName: The name used in contextual help output.
    ///   - environment: The environment used for executable and default resolution.
    ///   - fileSystem: File-system boundary used to locate the child executables.
    ///   - processRunnerFactory: Factory creating supervised child process runners.
    ///   - portProbe: Service probe used for port availability and readiness.
    ///   - tempDirProvider: Provider creating the temporary Mosquitto configuration directory.
    ///   - installSignalHandler: Whether the service runners install their own Ctrl-C handler.
    public init(
        executableName: String = "axoloty-tool",
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileSystem: any AxolotyDebugFileSystem = FoundationDebugFileSystem(),
        processRunnerFactory: @escaping @Sendable () -> any AxolotyManagedProcessRunning = { FoundationProcessRunner() },
        portProbe: any AxolotyServiceProbing = FoundationServiceProbe(),
        tempDirProvider: any AxolotyTempDirectoryProvider = FoundationTempDirectoryProvider(),
        installSignalHandler: Bool = false
    ) {
        self.executableName = executableName
        self.environment = environment
        self.fileSystem = fileSystem
        self.processRunnerFactory = processRunnerFactory
        self.portProbe = portProbe
        self.tempDirProvider = tempDirProvider
        self.installSignalHandler = installSignalHandler
    }

    /// Requests termination of the running service.
    public func cancel() {
        cancellation.cancel()
    }

    /// Parses and executes one serve command.
    ///
    /// - Parameter arguments: Arguments after the `serve` keyword.
    /// - Returns: The standard streams and status for the invocation.
    public func run(arguments: [String]) -> AxolotyServeResult {
        let parser = AxolotyServeParser()
        switch parser.parse(arguments: arguments, environment: environment) {
        case .success(let command):
            switch command {
            case .help(let topic):
                return AxolotyServeResult(
                    standardOutput: AxolotyServeHelp.usage(topic: topic, executableName: executableName)
                )
            case .mqtt(let config):
                let runner = AxolotyMQTTServiceRunner(
                    processRunner: processRunnerFactory(),
                    portProbe: portProbe,
                    fileSystem: fileSystem,
                    tempDirProvider: tempDirProvider,
                    mosquittoExecutable: environment["AXOLOTY_MOSQUITTO_EXECUTABLE"] ?? "/usr/sbin/mosquitto",
                    installSignalHandler: installSignalHandler,
                    cancellation: cancellation
                )
                return AxolotyServeResult(exitCode: runner.run(config))
            case .mcp(let config):
                let runner = AxolotyMCPServiceRunner(
                    processRunner: processRunnerFactory(),
                    portProbe: portProbe,
                    fileSystem: fileSystem,
                    mcpExecutable: environment["AXOLOTY_MCP_EXECUTABLE"] ?? "/opt/axoloty/bin/axoloty-mcp",
                    installSignalHandler: installSignalHandler,
                    cancellation: cancellation
                )
                return AxolotyServeResult(exitCode: runner.run(config))
            case .development(let config):
                let runner = AxolotyDevelopmentServiceRunner(
                    processRunnerFactory: processRunnerFactory,
                    portProbe: portProbe,
                    fileSystem: fileSystem,
                    tempDirProvider: tempDirProvider,
                    mosquittoExecutable: environment["AXOLOTY_MOSQUITTO_EXECUTABLE"] ?? "/usr/sbin/mosquitto",
                    mcpExecutable: environment["AXOLOTY_MCP_EXECUTABLE"] ?? "/opt/axoloty/bin/axoloty-mcp",
                    installSignalHandler: installSignalHandler,
                    cancellation: cancellation
                )
                return AxolotyServeResult(exitCode: runner.run(config))
            }
        case .failure(let error):
            return AxolotyServeResult(
                standardError: "error: \(error.userFriendlyMessage)\n",
                exitCode: 64
            )
        }
    }
}
