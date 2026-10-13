// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

/// Contextual usage text for the serve subcommands.
public enum AxolotyServeHelp {
    /// Returns the contextual usage for one serve subcommand.
    ///
    /// - Parameters:
    ///   - topic: The serve subcommand whose help was requested.
    ///   - executableName: The name used in the usage line.
    /// - Returns: The usage document with the executable name substituted.
    public static func usage(topic: AxolotyServeHelpTopic, executableName: String) -> String {
        let usage = switch topic {
        case .mqtt: mqttUsageDocument
        case .mcp: mcpUsageDocument
        case .dev: developmentUsageDocument
        }
        return usage.replacingOccurrences(of: "axoloty-tool", with: executableName)
    }

    private static let mqttUsageDocument = """
    Usage: axoloty-tool serve mqtt [options]

    Start a local Mosquitto broker in the foreground.

    Options:
      --listen-host HOST  Bind the broker to HOST (default: 127.0.0.1).
      --port PORT         Listen on PORT (default: 1883).
      --output MODE       Use human or json output (default: human).
      --log-level LEVEL   Use error, warning, info, or debug (default: info).
      --help              Show this help.
    """

    private static let mcpUsageDocument = """
    Usage: axoloty-tool serve mcp --transport TRANSPORT [options]

    Start an Axoloty MCP server using stdio or loopback HTTP.

    Options:
      --transport MODE        Use stdio or http (required).
      --listen-host HOST      HTTP bind address (default: 127.0.0.1).
      --listen-port PORT      HTTP listen port (default: 8765).
      --path PATH             HTTP endpoint path (default: /mcp).
      --broker-host HOST      MQTT broker host (default: localhost).
      --broker-port PORT      MQTT broker port (default: 1883).
      --namespace NAMESPACE   Coaty namespace (default: -).
      --connect-timeout TIME  Broker readiness timeout (default: 10s).
      --output MODE           HTTP output: human or json (default: human).
      --help                  Show this help.

    The HTTP-specific options are not valid with --transport stdio.
    """

    private static let developmentUsageDocument = """
    Usage: axoloty-tool serve dev [options]

    Start MQTT and MCP as a supervised local development stack.

    Options:
      --namespace NAMESPACE  Coaty namespace (default: -).
      --mqtt-port PORT       MQTT listen port (default: 1883).
      --mcp-port PORT        MCP HTTP listen port (default: 8765).
      --output MODE          Use human or json output (default: human).
      --help                 Show this help.
    """
}
