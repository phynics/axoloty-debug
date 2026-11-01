# Agent instructions for axoloty-debug

This file is the contributor policy for this repository. It owns the runtime
and debug tooling behind the Core build harness command `axoloty-tool serve`.

## Related repositories

[`phynics/axoloty`](https://github.com/phynics/axoloty) is Core. It owns the
portable protocol, runtime, Coaty models, and the build/test orchestration
(`axoloty-tool`, `AxolotyTooling`). Its
[`AGENTS.md`](https://github.com/phynics/axoloty/blob/main/AGENTS.md) governs
changes there. Core's `Tools` package is a library-free harness and does not
link this package; the Core container's `serve-*` targets invoke this
repository's `axoloty-debug` binary.

[`phynics/axoloty-embedded`](https://github.com/phynics/axoloty-embedded) owns
concrete firmware products and device qualification.

## Ownership boundary

This repository owns:

- the `axoloty-debug` CLI and the `serve mqtt|mcp|dev` command surface and its
  parser,
- the managed Mosquitto and `axoloty-mcp` service runners and the development
  stack supervisor,
- the object inspector (`axoloty-inspect`, `AxolotyInspectorCore`,
  `AxolotyInspectorRuntime`) and the MCP server (`axoloty-mcp`, `AxolotyMCP`),
- the package version resolver (`AxolotyVersion`),
- the process-launch and signal-disposition shim (`AxolotyProcessLauncher`),
- the `MCPPathPolicy` helper.

It does not own build, test, release, or repository-authority policy. Nothing
here may read the Axoloty checkout layout, a test manifest, or a package list.
It reaches a live runtime through the public Axoloty API only.

This package depends on the versioned Core release repository
(`https://github.com/phynics/axoloty.git`, `1.x` from `1.0.0`). For local Core development,
the environment variable `AXOLOTY_LOCAL_CORE_PATH` (or `AXOLOTY_CORE_PATH`) overrides
the package dependency to point to a local directory checkout. Core does not link
this package, and this package must not depend on Core's build harness (`Tools`).
Keep the `axoloty-debug`, `axoloty-inspect`, and `axoloty-mcp` executable names stable:
the Core container's `serve-*` targets invoke `axoloty-debug`.

## Invariants

- The only Axoloty input is the public library. Never read Core's source tree,
  `Tools`, a test manifest, its `.build`, or its checkout layout.
- The embedding process owns signals. Service runners take `installSignalHandler`
  and an `AxolotyDebugCancellation`; they never install a handler the caller did
  not ask for.
- Machine-readable readiness JSON goes to standard output; human readiness and
  diagnostics go to standard error. Keep that split.
- `AxolotyProcessLauncher` stays a thin C shim: process launch, exit-code
  decoding, and signal-disposition capture are its whole surface.

## Supported workflow

Swift Testing is the only test framework:

```sh
swift build
swift test
```

By default, Swift Package Manager resolves `Axoloty` from `https://github.com/phynics/axoloty.git` (1.x, from `1.0.0`).
To develop against a local Core checkout, set `AXOLOTY_LOCAL_CORE_PATH`:

```sh
AXOLOTY_LOCAL_CORE_PATH=/path/to/axoloty swift build
AXOLOTY_LOCAL_CORE_PATH=/path/to/axoloty swift test
```

CI builds and tests `axoloty-debug` standalone on Linux without requiring a sibling checkout.

## Platform support

- **Linux (Ubuntu / Jammy, Swift 6.4+):** Validated. Canonical target platform running in automated CI.
- **macOS:** Best-effort. Supported for local development on macOS 26+ / Darwin. CI runs on Linux only.

## Releases

`VERSION` is the single source of truth. To release, set `VERSION` to the new
semantic version, tag `vX.Y.Z`, and push the tag. The release workflow verifies
that `VERSION` matches the tag before creating the GitHub release.

## Source conventions

- Add `// Copyright (c) <year> <contributor>. Licensed under the MIT License.`
  to new comment-capable source files, using the first publication year.
- Add DocC to public types, properties, methods, initializers, and protocols.
  Document parameters, returns, and errors when present.
- Spell the error type on new and changed signatures (`throws(SomeError)`).
- Write Swift tests with Swift Testing, never XCTest.

## GitHub-centered work

- Fetch and compare `origin/main` before branching.
- Keep designs, plans, and decisions in GitHub issues or comments.
- One fix per PR, opened against `main`.
- Use Conventional Commits with the configured identity and no bot co-author
  trailer.
- Ask before creating an issue the user did not request.
