# Local services

The `axoloty-debug` CLI provides one foreground command surface for the local
Mosquitto broker and the Axoloty MCP server:

```sh
axoloty-debug serve mqtt
axoloty-debug serve mcp --transport stdio
axoloty-debug serve mcp --transport http   # http://127.0.0.1:8765/mcp
axoloty-debug serve dev                    # MQTT 127.0.0.1:1883 + MCP HTTP 127.0.0.1:8765/mcp
```

Every service remains in the foreground. Press Ctrl-C to stop it. The commands
return 64 for invalid arguments, 69 when an executable is missing or a port is
occupied, 70 for setup, start, or readiness failures, and 130 when
interrupted. Standalone MQTT and MCP commands return 1 when their child exits
nonzero; the development stack returns the exiting child's status. A normally
exiting child returns 0.

## Installation and wrappers

Build and run the products from this package:

```sh
swift run axoloty-debug serve mqtt
swift run axoloty-debug serve mcp --transport http
swift run axoloty-debug serve dev
```

The Core container ships a mounted-worktree launcher at
`/opt/axoloty/bin/axoloty-debug`. It runs this product with `swift run` against
the mounted checkout. For `serve mcp` and `serve dev`, it first builds the
`axoloty-mcp` product from this package and passes its executable path to the
service runner. This keeps MCP readiness timing separate from SwiftPM
compilation. An explicit `AXOLOTY_MCP_EXECUTABLE` skips that preparation step.
The Core repository exposes it through thin wrappers:

```sh
make serve-mqtt
make serve-mcp                              # stdio transport
make serve-mcp SERVE_MCP_ARGS='--transport http'
make serve-dev
```

The wrappers use host networking because services bind only to loopback; no
service policy is implemented in Make or shell.

## MQTT service

`axoloty-debug serve mqtt` starts Mosquitto with an ephemeral generated
configuration. It defaults to `127.0.0.1:1883`; use `--listen-host`, `--port`,
`--output`, and `--log-level` to configure its address, port, readiness format,
and diagnostic level. It reports readiness after accepting TCP connections,
with a five-second deadline.

## MCP service

`axoloty-debug serve mcp` requires one of these explicit transports:

- `--transport stdio` runs JSON-RPC over standard input and output and opens no
  listener. Do not write diagnostics to standard output.
- `--transport http` serves Streamable HTTP at
  `--listen-host`/`--listen-port`/`--path`, defaulting to
  `127.0.0.1:8765/mcp`. HTTP binds only to loopback and has a ten-second
  readiness deadline.

Both transports accept `--broker-host`, `--broker-port`, and `--namespace` to
connect to MQTT, plus `--connect-timeout`. HTTP also accepts `--listen-host`,
`--listen-port`, `--path`, and `--output`.

The server exposes the read-only resources `axoloty://status` and
`axoloty://catalogue`, plus these tools:

- `axoloty_list_objects` lists objects in the passive catalogue.
- `axoloty_get_object` retrieves a catalogue object by ID.
- `axoloty_discover_objects` sends one bounded Discover request and collects
  Resolve responses.
- `axoloty_server_status` reports MQTT connection state and catalogue metrics.

The catalogue is deliberately incomplete: it contains only objects advertised
after the observer connected. The server offers no arbitrary MQTT publish or
subscribe operation. Keep HTTP loopback-only; expose it remotely only through
an authenticated, deliberately configured proxy.

## Development stack

`axoloty-debug serve dev` starts MQTT first, waits for it, starts MCP HTTP,
then reports both endpoints. The launcher prepares `axoloty-mcp` before this
sequence starts. It defaults to MQTT port 1883 and MCP port 8765. Use
`--mqtt-port`, `--mcp-port`, `--namespace`, and `--output human|json` to change
the ports, namespace, and readiness format. If either child exits, the runner
terminates its sibling and returns the exiting child's status.
