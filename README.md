# Axoloty Debug (`axoloty-debug`)

Runtime and debug tooling for the Axoloty distributed robotics and IoT framework.

`axoloty-debug` provides debug CLIs, managed service runners, the object inspector, and the Model Context Protocol (MCP) server for inspecting and interacting with live Axoloty networks.

## Features & Executables

- **`axoloty-debug`**: CLI runner managing development service stacks (`serve mqtt`, `serve mcp`, `serve dev`).
- **`axoloty-inspect`**: Coaty and Zenoh object and topology inspector (`catalog`, `discover`, `diagnostics`, `decode`).
- **`axoloty-mcp`**: Model Context Protocol (MCP) server exposing Axoloty discovery, telemetry, and status to LLM agents and debug orchestrators over stdio or HTTP.

## Runtime diagnostics

`axoloty-inspect diagnostics` collects Core's bounded runtime diagnostic stream
and writes a versioned JSON export to standard output. Detail strings and
source, object, and correlation IDs are redacted by default. An explicit
`--capture-dir PATH` enables bounded rolling JSONL capture; `--reveal-detail`
and `--reveal-identities` opt in to retaining those values.

```sh
axoloty-inspect diagnostics --duration 30s
axoloty-inspect diagnostics --duration 30s --capture-dir ./diagnostics
```

MCP exposes the same history through the read-only `axoloty_get_diagnostics`
tool and the `axoloty://diagnostics` resource. MCP always reapplies default
redaction before returning an export.

## MCP access policy

MCP is read-only by default: raw payloads and private data are redacted, and
the bounded `axoloty_discover_objects` control requires `--enable-controls`.
A non-loopback HTTP listener is always read-only and requires
`--access-token-file PATH`; every request must then present that bearer token.
The token file must be a regular file with no group/world permissions and at
most 4 KiB of UTF-8 content.
A listener with access protection is remote even on loopback, so controls stay
unavailable behind a local reverse proxy. See `docs/services.md`.

## Installation & Building

Requirements:
- Swift 6.4 or later
- Optional for `axoloty-debug serve mqtt|dev`: `mosquitto` broker binary

```bash
swift build
swift test
```

### Prebuilt Linux binaries

Each `vX.Y.Z` release attaches `axoloty-debug-vX.Y.Z-linux-{x86_64,aarch64}.tar.gz`
(with a `.sha256` file) containing `axoloty-debug`, `axoloty-inspect`, and `axoloty-mcp`:

```sh
gh release download vX.Y.Z -R phynics/axoloty-debug -p 'axoloty-debug-*-linux-x86_64.tar.gz*'
sha256sum -c axoloty-debug-vX.Y.Z-linux-x86_64.tar.gz.sha256
```

### Container image

Releases also publish `ghcr.io/phynics/axoloty-debug:<version>` (linux/amd64 and
linux/arm64, includes Mosquitto). Other images can take the binaries directly:

```dockerfile
COPY --from=ghcr.io/phynics/axoloty-debug:X.Y.Z /usr/local/bin/axoloty-debug /usr/local/bin/
```

## Dependency Configuration & Local Core Overrides

By default, this package requires Axoloty Core `1.0.0..<2.0.0` from
`https://github.com/phynics/axoloty.git`. `Package.resolved` records Core
`1.0.0` at revision `b5e3df00ab9ac6e54ef1ff233d676d298209f9c0`.

### Local Development Override

When developing against an active local checkout of `phynics/axoloty`, you can direct Swift Package Manager to your local Core path using the `AXOLOTY_LOCAL_CORE_PATH` (or `AXOLOTY_CORE_PATH`) environment variable:

```bash
export AXOLOTY_LOCAL_CORE_PATH=/path/to/axoloty
swift build
swift test
```

When unset or empty, Swift Package Manager resolves the versioned Core dependency from GitHub without requiring a sibling checkout layout.

## Platform Support

In accordance with the Axoloty host platform matrix:

- **Linux (Ubuntu 22.04 LTS / Jammy, container `swift:6.4-jammy`):** **Validated**. Canonical target platform validated by automated CI on pushes to `main` and on pull requests.
- **macOS:** **Best-effort**. Maintained for local developer workflows on macOS 26+ (Apple Silicon and Intel). Automated CI runs on Linux only.

## CI & Automated Testing

CI is configured via GitHub Actions (`.github/workflows/ci.yml`) and runs tests inside a Linux container without requiring an implicit sibling checkout layout.

## License

MIT License. See [LICENSE](LICENSE) for details.
