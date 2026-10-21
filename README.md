# Axoloty Debug (`axoloty-debug`)

Runtime and debug tooling for the Axoloty distributed robotics and IoT framework.

`axoloty-debug` provides debug CLIs, managed service runners, the object inspector, and the Model Context Protocol (MCP) server for inspecting and interacting with live Axoloty networks.

## Features & Executables

- **`axoloty-debug`**: CLI runner managing development service stacks (`serve mqtt`, `serve mcp`, `serve dev`).
- **`axoloty-inspect`**: Coaty and Zenoh object and topology inspector (`catalog`, `discover`, `decode`).
- **`axoloty-mcp`**: Model Context Protocol (MCP) server exposing Axoloty discovery, telemetry, and status to LLM agents and debug orchestrators over stdio or HTTP.

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

## Dependency Configuration & Local Core Overrides

By default, `axoloty-debug` resolves the versioned Axoloty Core dependency from GitHub:
- `https://github.com/phynics/axoloty.git` (0.9.x, from `0.9.0`)

### Local Development Override

When developing against an active local checkout of `phynics/axoloty`, you can direct Swift Package Manager to your local Core path using the `AXOLOTY_LOCAL_CORE_PATH` (or `AXOLOTY_CORE_PATH`) environment variable:

```bash
export AXOLOTY_LOCAL_CORE_PATH=/path/to/axoloty
swift build
swift test
```

When unset or empty, SPM resolves the tagged release from GitHub without requiring a sibling checkout layout.

## Platform Support

In accordance with the Axoloty host platform matrix:

- **Linux (Ubuntu 22.04 LTS / Jammy, container `swift:6.4-jammy`):** **Validated**. Canonical target platform validated by automated CI on pushes to `main` and on pull requests.
- **macOS:** **Best-effort**. Maintained for local developer workflows on macOS 26+ (Apple Silicon and Intel). Automated CI runs on Linux only.

## CI & Automated Testing

CI is configured via GitHub Actions (`.github/workflows/ci.yml`) and runs tests inside a Linux container without requiring an implicit sibling checkout layout.

## License

MIT License. See [LICENSE](LICENSE) for details.
